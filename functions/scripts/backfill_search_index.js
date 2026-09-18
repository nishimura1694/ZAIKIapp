"use strict";

// 既存の bookings / venues ドキュメントのうち searchPrefixes が
// 未設定のものに検索用インデックス（searchText / searchPrefixes）を
// 一括で追加するバックフィルスクリプト。
//
// ロジックは lib/core/shared_models.dart の
// _normalizeSearchText / _buildSearchPrefixes / _buildBookingSearchIndex /
// _buildVenueSearchIndex と同一になるよう移植している。
//
// 使い方:
//   node functions/scripts/backfill_search_index.js          # 未設定分のみ本番に書き込み
//   DRY_RUN=1 node functions/scripts/backfill_search_index.js # 件数確認のみ
//   REGEN_ALL=1 node functions/scripts/backfill_search_index.js # 既存分も含め全件再生成

const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

const PROJECT_ID = "coffee-spark-ai-barista-844b4";
const DRY_RUN = process.env.DRY_RUN === "1";
const REGEN_ALL = process.env.REGEN_ALL === "1";

initializeApp({
  credential: applicationDefault(),
  projectId: PROJECT_ID,
});

const db = getFirestore();

const COLLAPSE_WHITESPACE = /\s+/g;
const WORD_SPLIT_PATTERN = /[\s、。・/\\\-_,.()]+/;
const PREFIX_MAX_LENGTH = 24;

function toHiragana(input) {
  let result = "";
  for (const ch of input) {
    const code = ch.codePointAt(0);
    if (code >= 0x30a1 && code <= 0x30f6) {
      result += String.fromCodePoint(code - 0x60);
    } else {
      result += ch;
    }
  }
  return result;
}

function normalizeSearchText(input) {
  return toHiragana(
    input.toLowerCase().trim().replace(COLLAPSE_WHITESPACE, " "),
  );
}

// 「株式会社トラスト」のように区切り文字なしで単語が連結されている
// 場合でも、後半の単語（トラスト）で前方一致検索できるように、
// 漢字/かな/英数字の切り替わり目でも追加のサブトークンを作る。
function scriptClassOf(codeUnit) {
  if (codeUnit >= 0x4e00 && codeUnit <= 0x9fff) return 0; // 漢字
  if (
    (codeUnit >= 0x30 && codeUnit <= 0x39) ||
    (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
    (codeUnit >= 0x41 && codeUnit <= 0x5a)
  ) {
    return 1; // 英数字
  }
  return 2; // かな・その他
}

function splitByScript(token) {
  if (token.length <= 1) return [token];

  const runs = new Set();
  let buffer = "";
  let currentClass = null;
  for (let i = 0; i < token.length; i++) {
    const cls = scriptClassOf(token.charCodeAt(i));
    if (currentClass !== null && cls !== currentClass && buffer) {
      runs.add(buffer);
      buffer = "";
    }
    buffer += token[i];
    currentClass = cls;
  }
  if (buffer) runs.add(buffer);
  return Array.from(runs);
}

function buildSearchPrefixes(input) {
  const normalized = normalizeSearchText(input);
  if (!normalized) return [];

  const tokens = new Set([normalized]);
  for (const part of normalized.split(WORD_SPLIT_PATTERN)) {
    const trimmed = part.trim();
    if (trimmed) tokens.add(trimmed);
  }
  for (const token of Array.from(tokens)) {
    for (const run of splitByScript(token)) {
      tokens.add(run);
    }
  }

  const prefixes = new Set();
  for (const token of tokens) {
    const maxLen = Math.min(token.length, PREFIX_MAX_LENGTH);
    for (let i = 1; i <= maxLen; i++) {
      prefixes.add(token.substring(0, i));
    }
  }

  return Array.from(prefixes).sort();
}

function buildBookingSearchIndex(customerName, venueName) {
  const source = `${String(customerName || "").trim()} ${String(
    venueName || "",
  ).trim()}`.trim();
  return {
    searchText: normalizeSearchText(source),
    searchPrefixes: buildSearchPrefixes(source),
  };
}

function buildVenueSearchIndex(name, shopAndRoom) {
  const source = `${String(name || "").trim()} ${String(
    shopAndRoom || "",
  ).trim()}`.trim();
  return {
    searchText: normalizeSearchText(source),
    searchPrefixes: buildSearchPrefixes(source),
  };
}

async function backfillCollection({ collectionName, buildIndex }) {
  const snapshot = await db.collection(collectionName).get();
  let updated = 0;
  let skipped = 0;
  let emptySource = 0;
  let batch = db.batch();
  let opsInBatch = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const existing = data.searchPrefixes;
    if (!REGEN_ALL && Array.isArray(existing) && existing.length > 0) {
      skipped++;
      continue;
    }

    const index = buildIndex(data);
    if (index.searchPrefixes.length === 0) {
      emptySource++;
      continue;
    }

    if (REGEN_ALL) {
      const existingSorted = Array.isArray(existing)
        ? Array.from(existing).sort()
        : [];
      const nextSorted = Array.from(index.searchPrefixes).sort();
      const unchanged =
        existingSorted.length === nextSorted.length &&
        existingSorted.every((v, i) => v === nextSorted[i]);
      if (unchanged) {
        skipped++;
        continue;
      }
    }

    if (!DRY_RUN) {
      batch.update(doc.ref, {
        searchText: index.searchText,
        searchPrefixes: index.searchPrefixes,
      });
      opsInBatch++;
      if (opsInBatch >= 400) {
        await batch.commit();
        batch = db.batch();
        opsInBatch = 0;
      }
    }
    updated++;
  }

  if (!DRY_RUN && opsInBatch > 0) {
    await batch.commit();
  }

  console.log(
    `[${collectionName}] total=${snapshot.size} updated=${updated} ` +
      `alreadyIndexed=${skipped} emptySource=${emptySource} ` +
      `dryRun=${DRY_RUN} regenAll=${REGEN_ALL}`,
  );
}

async function main() {
  await backfillCollection({
    collectionName: "bookings",
    buildIndex: (data) =>
      buildBookingSearchIndex(data.customerName, data.venueName),
  });

  await backfillCollection({
    collectionName: "venues",
    buildIndex: (data) => buildVenueSearchIndex(data.name, data.shopAndRoom),
  });
}

main()
  .then(() => {
    console.log("Backfill complete.");
    process.exit(0);
  })
  .catch((err) => {
    console.error("Backfill failed:", err);
    process.exit(1);
  });
