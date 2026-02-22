import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image/image.dart' as img;
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
// 位置情報の自動取得を避けるため、明示的な Geolocator のチェックは行わない
import 'package:http/http.dart' as http;
import 'firebase_options.dart';
import 'package:geolocator/geolocator.dart'; // ←追加

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const VenueApp());
}

// --- モデルクラス ---
class PhotoItem {
  final String url;
  final String venueName;
  final String docId;
  final Map<String, dynamic> data;
  PhotoItem(this.url, this.venueName, this.docId, this.data);
}

class VenueApp extends StatelessWidget {
  const VenueApp({super.key});

  @override
  Widget build(BuildContext context) {
    const Color brandOrange = Color.fromARGB(255, 255, 102, 0);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ZAIKIナビ',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        fontFamily: GoogleFonts.mPlus2().fontFamily,
        colorScheme: ColorScheme.fromSeed(seedColor: brandOrange, surface: Colors.white),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
          iconTheme: IconThemeData(color: Colors.black),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

// --- 共通コンポーネント ---
Widget _detailRow(IconData icon, String label, String? value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 20, color: Colors.grey[700]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(value == null || value.isEmpty ? "-" : value, style: const TextStyle(fontSize: 16, color: Colors.black87, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    ),
  );
}

// --- メインナビゲーション ---
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});
  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  final List<Widget> _pages = [
    const VenueListScreen(),
    const BookingListScreen(),
  ];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.location_on_outlined), label: '会場'),
          BottomNavigationBarItem(icon: Icon(Icons.history_outlined), label: '履歴'),
        ],
      ),
    );
  }
}

// --- 写真ギャラリー ---
// Photo gallery removed per request.

// --- 会場一覧 ---
class VenueListScreen extends StatefulWidget {
  const VenueListScreen({super.key});
  @override
  State<VenueListScreen> createState() => _VenueListScreenState();
}

class _VenueListScreenState extends State<VenueListScreen> {
  String _searchQuery = "";
  String _selectedBlock = "すべて";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('会場一覧'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                height: 50,
                child: TextField(
                  decoration: const InputDecoration(hintText: '会場名・部屋名で検索...', prefixIcon: Icon(Icons.search), contentPadding: EdgeInsets.zero),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
            ),
            SizedBox(
              height: 45,
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('blocks').orderBy('name').snapshots(),
                builder: (context, snapshot) {
                  List<String> blocks = ["すべて"];
                  if (snapshot.hasData) blocks.addAll(snapshot.data!.docs.map((d) => d['name'] as String));
                  return ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: blocks.map((block) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(block),
                        selected: _selectedBlock == block,
                        onSelected: (selected) => setState(() => _selectedBlock = block),
                        selectedColor: Theme.of(context).colorScheme.primaryContainer,
                      ),
                    )).toList(),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('venues').orderBy('name').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final name = (data['name'] ?? '').toString().toLowerCase();
            return name.contains(_searchQuery.toLowerCase()) && (_selectedBlock == "すべて" || data['block'] == _selectedBlock);
          }).toList();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: docs.length,
            separatorBuilder: (_, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final hasAddress = (data['address'] ?? '').toString().isNotEmpty;
              return Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFEEEEEE))),
                child: ListTile(
                  title: Text(data['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${data['block'] ?? '-'} / ${data['shopAndRoom'] ?? '-'}"),
                  trailing: SizedBox(
                    width: 48,
                    child: hasAddress
                      ? IconButton(
                          icon: const Icon(Icons.location_on),
                          color: const Color.fromARGB(255, 255, 102, 0),
                          onPressed: () async {
                            final address = data['address'] ?? '';
                            final String uri = 'https://maps.google.com/?q=${Uri.encodeComponent(address)}';
                            try {
                              if (await canLaunchUrl(Uri.parse(uri))) {
                                await launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication);
                              } else {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('地図アプリを開けませんでした')));
                                }
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
                              }
                            }
                          },
                        )
                      : const Icon(Icons.location_on),
                  ),
                  onTap: () => showModalBottomSheet(
                    context: context, 
                    isScrollControlled: true, 
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                    builder: (_) => VenueDetailSheet(data: data, docId: docs[index].id)
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddVenueScreen())),
        backgroundColor: const Color.fromARGB(255, 255, 102, 0),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('会場を追加'),
      ),
    );
  }
}

// --- 予約履歴一覧 ---
class BookingListScreen extends StatefulWidget {
  const BookingListScreen({super.key});
  @override
  State<BookingListScreen> createState() => _BookingListScreenState();
}

class _BookingListScreenState extends State<BookingListScreen> {
  String _searchQuery = "";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('予約履歴'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(hintText: '顧客・会場名で検索...', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('bookings').orderBy('bookingDate', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final customer = (data['customerName'] ?? '').toString().toLowerCase();
            final venue = (data['venueName'] ?? '').toString().toLowerCase();
            return customer.contains(_searchQuery.toLowerCase()) || venue.contains(_searchQuery.toLowerCase());
          }).toList();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: docs.length,
            separatorBuilder: (_, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final List urls = data['imageUrls'] ?? [];

              return Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFEEEEEE))),
                child: ListTile(
                  leading: urls.isNotEmpty 
                    ? ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(urls[0], width: 50, height: 50, fit: BoxFit.cover)) 
                    : Container(width: 50, height: 50, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(6)), child: const Icon(Icons.image_outlined, color: Colors.grey)),
                  title: Text(data['customerName'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${data['bookingDate']} / ${data['venueName']}"),
                  // trailingアイコンを削除
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                    builder: (_) => BookingDetailSheet(data: data, docId: docs[index].id),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddBookingScreen())),
        backgroundColor: const Color.fromARGB(255, 255, 102, 0),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.post_add),
        label: const Text('予約を登録'),
      ),
    );
  }
}

// --- 会場マップビュー ---
class VenueMapScreen extends StatefulWidget {
  const VenueMapScreen({super.key});
  @override
  State<VenueMapScreen> createState() => _VenueMapScreenState();
}

class _VenueMapScreenState extends State<VenueMapScreen> {
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _loadVenueMarkers();
  }

  Future<void> _loadVenueMarkers() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('venues').get();
      final markers = <Marker>[];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final lat = data['latitude'] as double?;
        final lng = data['longitude'] as double?;

        if (lat != null && lng != null) {
          final markerId = MarkerId(doc.id);
          markers.add(
            Marker(
              markerId: markerId,
              position: LatLng(lat, lng),
              infoWindow: InfoWindow(title: data['name'] ?? ''),
              onTap: () => _showVenueDetail(doc.id, data),
            ),
          );

        }
      }

      setState(() {
        _markers = markers.toSet();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('会場の読み込みに失敗しました: $e')));
      }
    }
  }

  void _showVenueDetail(String docId, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => VenueDetailSheet(data: data, docId: docId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('会場マップ'),
        elevation: 0,
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(target: LatLng(35.6762, 139.6503), zoom: 12),
        markers: _markers,
        zoomControlsEnabled: true,
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'refresh',
            onPressed: _loadVenueMarkers,
            backgroundColor: Colors.white,
            foregroundColor: const Color.fromARGB(255, 255, 102, 0),
            tooltip: '更新',
            child: const Icon(Icons.refresh),
          ),
          const SizedBox(height: 16),
          FloatingActionButton.extended(
            heroTag: 'add',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddVenueScreen())),
            backgroundColor: const Color.fromARGB(255, 255, 102, 0),
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('会場を追加'),
          ),
        ],
      ),
    );
  }
}

// --- 予約詳細シート ---
class BookingDetailSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  const BookingDetailSheet({super.key, required this.data, required this.docId});

  void _showImageGallery(BuildContext context, List urls, int startIndex) {
    final controller = PageController(initialPage: startIndex);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.9, maxHeight: MediaQuery.of(context).size.height * 0.9),
          child: Stack(children: [
            PageView.builder(
              controller: controller,
              itemCount: urls.length,
              itemBuilder: (context, i) => InteractiveViewer(child: Image.network(urls[i], fit: BoxFit.contain)),
            ),
            Positioned(top: 8, right: 8, child: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(ctx).pop())),
          ]),
        ),
      ),
    );
  }

  Future<void> _launchURL(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url.trim().startsWith('http') ? url.trim() : 'https://${url.trim()}');
    try {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('リンクを開けませんでした')));
      }
    }
  }

  Future<void> _deleteBooking(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除の確認'),
        content: const Text('この予約履歴を削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('削除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      await FirebaseFirestore.instance.collection('bookings').doc(docId).delete();
      if (context.mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List urls = data['imageUrls'] ?? [];
    return DraggableScrollableSheet(
      initialChildSize: 0.8, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
      builder: (_, controller) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(children: [
          Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          Expanded(
            child: ListView(
              controller: controller,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Expanded(child: Text(data['customerName'] ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
                  Row(children: [
                    IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => AddBookingScreen(docId: docId, initialData: data))); }),
                    IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => _deleteBooking(context)),
                  ]),
                ]),
                const SizedBox(height: 24),
                _detailRow(Icons.calendar_today, '利用日', data['bookingDate']),
                _detailRow(Icons.location_on_outlined, '会場', data['venueName']),
                if (data['dropboxUrl'] != null && data['dropboxUrl'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: InkWell(
                      onTap: () => _launchURL(context, data['dropboxUrl']),
                      child: _detailRow(Icons.link, 'Dropboxリンク (タップで開く)', data['dropboxUrl']),
                    ),
                  ),
                const Divider(height: 32, color: Color(0xFFEEEEEE)),
                const Text('写真', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 12),
                if (urls.isEmpty) const Text('なし') else 
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10),
                  itemCount: urls.length,
                  itemBuilder: (context, i) => GestureDetector(
                    onTap: () => _showImageGallery(context, urls, i),
                    child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(urls[i], fit: BoxFit.cover)),
                  ),
                ),
                const SizedBox(height: 24),
                const Text('備考', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 8),
                Text(data['remarks'] ?? 'なし', style: const TextStyle(fontSize: 16, height: 1.6)),
                const SizedBox(height: 24),
                const Text('引継ぎ事項', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 8),
                Text(data['handover'] ?? 'なし', style: const TextStyle(fontSize: 16, height: 1.6, color: Colors.redAccent)),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// --- 会場詳細シート ---
class VenueDetailSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  const VenueDetailSheet({super.key, required this.data, required this.docId});

  Future<void> _deleteVenue(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('会場の削除'),
        content: const Text('この会場情報を削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('削除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      await FirebaseFirestore.instance.collection('venues').doc(docId).delete();
      if (context.mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
      builder: (_, controller) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(children: [
          Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          Expanded(
            child: ListView(
              controller: controller,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Expanded(child: Text(data['name'] ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
                  Row(children: [
                    IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => AddVenueScreen(docId: docId, initialData: data))); }),
                    IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => _deleteVenue(context)),
                  ]),
                ]),
                Text(data['shopAndRoom'] ?? '', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                const SizedBox(height: 32),
                _detailRow(Icons.grid_view, 'ブロック', data['block']),
                _detailRow(Icons.category, 'カテゴリ', data['category']),
                _detailRow(Icons.power, '電源仕様', data['power']),
                _detailRow(Icons.door_front_door, '搬入口・動線', data['loadingPort']),
                _detailRow(Icons.local_parking, '駐車場', data['parking']),
                _detailRow(Icons.groups, 'キャパシティ', data['capacity']),
                const SizedBox(height: 20),
                const Text('この会場の予約履歴', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 180,
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('bookings').where('venueId', isEqualTo: docId).snapshots(),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Center(child: Text('履歴の取得に失敗しました: ${snap.error}'));
                      }
                      if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                      var docs = snap.data?.docs ?? [];
                      docs.sort((a, b) {
                        final aDate = (a.data() as Map)['bookingDate']?.toString() ?? '';
                        final bDate = (b.data() as Map)['bookingDate']?.toString() ?? '';
                        return bDate.compareTo(aDate);
                      });
                      if (docs.isEmpty) return const Center(child: Text('履歴がありません'));
                      return ListView.separated(
                        itemCount: docs.length,
                        padding: EdgeInsets.zero,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final b = docs[i].data() as Map<String, dynamic>;
                          final List urls = b['imageUrls'] ?? [];
                          return InkWell(
                            onTap: () {
                              Navigator.pop(context);
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.white,
                                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                                builder: (_) => BookingDetailSheet(data: b, docId: docs[i].id),
                              );
                            },
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: urls.isNotEmpty
                                ? ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(urls[0], width: 50, height: 50, fit: BoxFit.cover))
                                : Container(width: 50, height: 50, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(6)), child: const Icon(Icons.image_outlined, color: Colors.grey)),
                              title: Text(b['customerName'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(b['bookingDate'] ?? '-'),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const Divider(height: 40, color: Color(0xFFEEEEEE)),
                const Text('備考', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 12),
                Text(data['remarks'] ?? 'なし', style: const TextStyle(fontSize: 16, height: 1.6)),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// --- 会場登録画面 ---
class AddVenueScreen extends StatefulWidget {
  final String? docId;
  final Map<String, dynamic>? initialData;
  const AddVenueScreen({super.key, this.docId, this.initialData});
  @override
  State<AddVenueScreen> createState() => _AddVenueScreenState();
}

// マップピッカー画面
class MapPickerScreen extends StatefulWidget {
  final double? initialLat, initialLng;
  const MapPickerScreen({super.key, this.initialLat, this.initialLng});
  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  late LatLng _selectedLocation;
  
  @override
  void initState() {
    super.initState();
    _selectedLocation = LatLng(widget.initialLat ?? 35.6762, widget.initialLng ?? 139.6503);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('位置を選択')),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(target: _selectedLocation, zoom: 15),
        onTap: (location) => setState(() => _selectedLocation = location),
        markers: {Marker(markerId: const MarkerId('selected'), position: _selectedLocation)},
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pop(context, _selectedLocation),
        backgroundColor: const Color.fromARGB(255, 255, 102, 0),
        label: const Text('この位置を選択'),
        icon: const Icon(Icons.check),
      ),
    );
  }
}

class _AddVenueScreenState extends State<AddVenueScreen> {
  // Google Geocoding API Key - ユーザーがGoogle Cloud Projectで設定する必要があります
  // https://console.cloud.google.com で Geocoding API を有効化して取得してください
  // static const String _googleMapsApiKey = 'AIzaSyCSfPC2LfzFf-7iav6ghQddG2IG3XCGFS0'; // 未使用のためコメントアウト
  
  final Map<String, TextEditingController> _controllers = {
    'name': TextEditingController(),
    'address': TextEditingController(), // 住所追加
    'shopAndRoom': TextEditingController(),
    'loadingPort': TextEditingController(),
    'parking': TextEditingController(),
    'capacity': TextEditingController(),
    'remarks': TextEditingController(),
  };
  String? _selectedBlock, _selectedCategory, _selectedPower;
  // 位置情報関連変数・タイマー・フラグ削除

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      widget.initialData!.forEach((key, val) {
        if (_controllers.containsKey(key)) _controllers[key]?.text = val.toString();
      });
      _selectedBlock = widget.initialData!['block'];
      _selectedCategory = widget.initialData!['category'];
      _selectedPower = widget.initialData!['power'];
      // 位置情報の初期化削除
    }
    
    // 建物名フィールドの変更リスナーは削除（確定時のみ取得）
  }

  @override
  void dispose() {
    _controllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  // 位置情報関連メソッド削除

  // ドロップダウン管理用メソッド追加
  void _manageItems(String col, String label) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$labelの管理'),
        content: SizedBox(
          width: 300,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection(col).snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const SizedBox();
              return ListView.builder(
                shrinkWrap: true,
                itemCount: snap.data!.docs.length,
                itemBuilder: (context, index) {
                  final doc = snap.data!.docs[index];
                  return ListTile(
                    title: Text(doc['name']),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _editItem(col, label, doc.id, doc['name'])),
                      IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.red), onPressed: () => _deleteItem(col, doc.id)),
                    ]),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる')),
          ElevatedButton(onPressed: () { Navigator.pop(ctx); _addNewItem(col, label); }, child: const Text('新規追加')),
        ],
      ),
    );
  }

  void _addNewItem(String col, String label) {
    final c = TextEditingController();
    if (!mounted) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text('$labelの追加'),
      content: TextField(controller: c, decoration: const InputDecoration(hintText: '名前を入力')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
        TextButton(onPressed: () async {
          if (c.text.isNotEmpty) {
            await FirebaseFirestore.instance.collection(col).add({'name': c.text});
            if (mounted) Navigator.pop(ctx);
          }
        }, child: const Text('追加')),
      ],
    ));
  }

  void _editItem(String col, String label, String id, String currentName) {
    final c = TextEditingController(text: currentName);
    if (!mounted) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text('$labelの編集'),
      content: TextField(controller: c, decoration: const InputDecoration(hintText: '新しい名前')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
        TextButton(onPressed: () async {
          if (c.text.isNotEmpty) {
            await FirebaseFirestore.instance.collection(col).doc(id).update({'name': c.text});
            if (mounted) Navigator.pop(ctx);
          }
        }, child: const Text('更新')),
      ],
    ));
  }

  Future<void> _deleteItem(String col, String id) async {
    await FirebaseFirestore.instance.collection(col).doc(id).delete();
  }

  Widget _buildDropdown(String label, String col, String? current, Function(String?) onChg) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection(col).orderBy('name').snapshots(),
      builder: (context, snap) {
        final items = snap.data?.docs.map((d) => d['name'] as String).toList() ?? [];
        return Row(children: [
          Expanded(child: DropdownButtonFormField<String>(
            initialValue: (current != null && items.contains(current)) ? current : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: label),
            items: items.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: onChg,
          )),
          const SizedBox(width: 4),
          IconButton(icon: const Icon(Icons.settings, color: Colors.grey), onPressed: () => _manageItems(col, label)),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.docId == null ? '会場の登録' : '会場の編集')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          TextField(
            controller: _controllers['name'],
            decoration: const InputDecoration(
              labelText: '建物名',
            ),
          ),
          const SizedBox(height: 15),
          TextField(controller: _controllers['shopAndRoom'], decoration: const InputDecoration(labelText: '部屋/店名')),
          const SizedBox(height: 15),
          _buildDropdown('ブロック', 'blocks', _selectedBlock, (v) => setState(() => _selectedBlock = v)),
          const SizedBox(height: 15),
          _buildDropdown('カテゴリ', 'categories', _selectedCategory, (v) => setState(() => _selectedCategory = v)),
          const SizedBox(height: 15),
          TextField(
            controller: _controllers['address'],
            decoration: const InputDecoration(
              labelText: '住所',
            ),
          ),
          const SizedBox(height: 15),
          TextField(controller: _controllers['loadingPort'], decoration: const InputDecoration(labelText: '搬入口/動線')),
          const SizedBox(height: 15),
          TextField(controller: _controllers['parking'], decoration: const InputDecoration(labelText: '駐車場')),
          const SizedBox(height: 15),
          _buildDropdown('電源', 'powers', _selectedPower, (v) => setState(() => _selectedPower = v)),
          const SizedBox(height: 15),
          TextField(controller: _controllers['capacity'], decoration: const InputDecoration(labelText: 'キャパ')),
          const SizedBox(height: 15),
          // 位置情報欄を削除
          const SizedBox(height: 15),
          TextField(controller: _controllers['remarks'], decoration: const InputDecoration(labelText: '備考'), maxLines: 3),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () async {
                final data = {
                  for (var e in _controllers.entries) e.key: e.value.text,
                  'block': _selectedBlock,
                  'category': _selectedCategory,
                  'power': _selectedPower,
                  'updatedAt': FieldValue.serverTimestamp()
                };
                String? docId = widget.docId;
                if (docId == null) {
                  final docRef = await FirebaseFirestore.instance.collection('venues').add(data);
                  docId = docRef.id;
                } else {
                  await FirebaseFirestore.instance.collection('venues').doc(docId).update(data);
                }
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 255, 102, 0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('会場情報を保存', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ]),
      ),
    );
  }
}

// --- 予約登録画面 ---
class AddBookingScreen extends StatefulWidget {
  final String? docId;
  final Map<String, dynamic>? initialData;
  const AddBookingScreen({super.key, this.docId, this.initialData});
  @override
  State<AddBookingScreen> createState() => _AddBookingScreenState();
}

class _AddBookingScreenState extends State<AddBookingScreen> {
  final _customerController = TextEditingController();
  final _dateController = TextEditingController();
  final _remarksController = TextEditingController();
  final _handoverController = TextEditingController();
  final _dropboxController = TextEditingController();
  final _venueSearchController = TextEditingController();
  
  String? _selectedVenueId, _selectedVenueName;
  final List<XFile> _imageFiles = [];
  final List<Uint8List> _webImageBytes = [];
  List<String> _existingUrls = [];
  bool _isUploading = false;
  bool _showVenueList = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      final d = widget.initialData!;
      _customerController.text = d['customerName'] ?? '';
      _dateController.text = d['bookingDate'] ?? '';
      _remarksController.text = d['remarks'] ?? '';
      _handoverController.text = d['handover'] ?? '';
      _dropboxController.text = d['dropboxUrl'] ?? '';
      _selectedVenueId = d['venueId'];
      _selectedVenueName = d['venueName'];
      _venueSearchController.text = d['venueName'] ?? '';
      _existingUrls = List<String>.from(d['imageUrls'] ?? []);
    }
  }

  Future<void> _quickRegisterVenue() async {
    final String venueName = _venueSearchController.text.trim();
    if (venueName.isEmpty) return;
    setState(() => _isUploading = true);
    try {
      final docRef = await FirebaseFirestore.instance.collection('venues').add({'name': venueName, 'createdAt': FieldValue.serverTimestamp()});
      setState(() {
        _selectedVenueId = docRef.id;
        _selectedVenueName = venueName;
        _showVenueList = false;
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('新規会場として登録しました')));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  // 画像リストへの追加／重複確認（Webとそれ以外で扱いを分ける）
  Future<void> _addPickedImage(XFile file) async {
    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      final exists = _webImageBytes.any((b) => listEquals(b, bytes));
      if (!exists) {
        setState(() => _webImageBytes.add(bytes));
      }
    } else {
      final exists = _imageFiles.any((f) => f.path == file.path);
      if (!exists) {
        setState(() => _imageFiles.add(file));
      }
    }
  }

  Future<void> _addPickedImages(List<XFile> files) async {
    for (var f in files) {
      await _addPickedImage(f);
    }
  }

  // ギャラリープレビュー（AddBookingScreen 用）: 既存URL と 選択画像 を連結して表示
  void _showGalleryFromAdd(int startIndex) {
    final existingLen = _existingUrls.length;
    final addedLen = kIsWeb ? _webImageBytes.length : _imageFiles.length;
    final total = existingLen + addedLen;
    final controller = PageController(initialPage: startIndex);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.9, maxHeight: MediaQuery.of(context).size.height * 0.9),
          child: Stack(children: [
            PageView.builder(
              controller: controller,
              itemCount: total,
              itemBuilder: (c, i) {
                if (i < existingLen) return InteractiveViewer(child: Image.network(_existingUrls[i], fit: BoxFit.contain));
                final idx = i - existingLen;
                if (kIsWeb) return InteractiveViewer(child: Image.memory(_webImageBytes[idx], fit: BoxFit.contain));
                return InteractiveViewer(child: Image.file(File(_imageFiles[idx].path), fit: BoxFit.contain));
              },
            ),
            Positioned(top: 8, right: 8, child: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(ctx).pop())),
          ]),
        ),
      ),
    );
  }

  // 画像バイト列をリサイズ＆圧縮し、200KB以下になるまで画質を下げて返す（失敗時は元データを返却）
  Uint8List _compressImageBytes(Uint8List data, {int maxWidth = 1600, int quality = 80, int maxBytes = 200 * 1024}) {
    try {
      final decoded = img.decodeImage(data);
      if (decoded == null) return data;
      final shouldResize = decoded.width > maxWidth;
      final out = shouldResize ? img.copyResize(decoded, width: maxWidth) : decoded;
      int q = quality;
      Uint8List encoded = Uint8List.fromList(img.encodeJpg(out, quality: q));
      // 200KB以下になるまで画質を下げて再圧縮
      while (encoded.lengthInBytes > maxBytes && q > 20) {
        q -= 10;
        encoded = Uint8List.fromList(img.encodeJpg(out, quality: q));
      }
      return encoded;
    } catch (_) {
      return data;
    }
  }

  void _save() async {
    if (_selectedVenueId == null || _customerController.text.isEmpty) {
      // print('会場IDまたは顧客名が未入力');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('会場と顧客名を入力してください')));
      return;
    }
    setState(() => _isUploading = true);
    try {
      List<String> newUrls = [];
      // print('アップロード開始: kIsWeb=$kIsWeb');
      if (kIsWeb) {
        final uploadFutures = List.generate(_webImageBytes.length, (i) async {
          final fileName = '${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
          // print('Web画像 $i: fileName=$fileName, size=${_webImageBytes[i].length}');
          final ref = FirebaseStorage.instance.ref().child('bookings/$fileName');
          final compressed = _compressImageBytes(_webImageBytes[i]);
          // print('圧縮後 size=${compressed.length}');
          await ref.putData(compressed, SettableMetadata(contentType: 'image/jpeg'));
          // print('putData complete: $fileName');
          final url = await ref.getDownloadURL();
          // print('getDownloadURL: $url');
          return url;
        });
        newUrls = await Future.wait(uploadFutures);
      } else {
        final uploadFutures = _imageFiles.map((file) async {
          final ref = FirebaseStorage.instance.ref().child('bookings/${DateTime.now().millisecondsSinceEpoch}_${file.name}');
          final raw = await file.readAsBytes();
          // print('ローカル画像: ${file.name}, size=${raw.length}');
          final compressed = _compressImageBytes(raw);
          // print('圧縮後 size=${compressed.length}');
          await ref.putData(compressed, SettableMetadata(contentType: 'image/jpeg'));
          // print('putData complete: ${file.name}');
          final url = await ref.getDownloadURL();
          // print('getDownloadURL: $url');
          return url;
        }).toList();
        newUrls = await Future.wait(uploadFutures);
      }
      // print('アップロード完了: newUrls=$newUrls');
      final data = {
        'customerName': _customerController.text,
        'bookingDate': _dateController.text,
        'venueId': _selectedVenueId,
        'venueName': _selectedVenueName,
        'remarks': _remarksController.text,
        'handover': _handoverController.text,
        'dropboxUrl': _dropboxController.text,
        'imageUrls': [..._existingUrls, ...newUrls],
        'updatedAt': FieldValue.serverTimestamp()
      };
      if (widget.docId == null) {
        // print('Firestore add: $data');
        await FirebaseFirestore.instance.collection('bookings').add(data);
      } else {
        // print('Firestore update: $data');
        await FirebaseFirestore.instance.collection('bookings').doc(widget.docId).update(data);
      }
      if (!mounted) return;
      // print('画面を閉じる');
      Navigator.pop(context);
    } catch (e) {
      // print('アップロード例外: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失敗: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.docId == null ? '予約の登録' : '予約の編集')),
      body: Stack(children: [
        SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _venueSearchController,
            decoration: InputDecoration(
              labelText: '会場を選択または新規入力', prefixIcon: const Icon(Icons.search),
              suffixIcon: _selectedVenueId == null && _venueSearchController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.add_circle, color: Colors.orange), onPressed: _quickRegisterVenue) : null,
            ),
            onChanged: (v) => setState(() => _showVenueList = true),
          ),
          if (_showVenueList) Container(
            constraints: const BoxConstraints(maxHeight: 200), margin: const EdgeInsets.only(top: 4), decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8), color: Colors.white),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('venues').snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const SizedBox();
                final filtered = snap.data!.docs.where((d) => d['name'].toString().toLowerCase().contains(_venueSearchController.text.toLowerCase())).toList();
                return ListView.builder(shrinkWrap: true, itemCount: filtered.length, itemBuilder: (ctx, i) => ListTile(title: Text(filtered[i]['name']), onTap: () => setState(() { _selectedVenueId = filtered[i].id; _selectedVenueName = filtered[i]['name']; _venueSearchController.text = filtered[i]['name']; _showVenueList = false; })));
              },
            ),
          ),
          const SizedBox(height: 15),
          TextField(controller: _customerController, decoration: const InputDecoration(labelText: '顧客名（案件名）')),
          const SizedBox(height: 15),
          TextField(controller: _dateController, decoration: const InputDecoration(labelText: '利用日', prefixIcon: Icon(Icons.calendar_today)), readOnly: true, onTap: () async {
            final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
            if (d != null) setState(() => _dateController.text = DateFormat('yyyy/MM/dd').format(d));
          }),
          const SizedBox(height: 15),
          TextField(controller: _dropboxController, decoration: const InputDecoration(labelText: 'Dropboxリンク')),
          const SizedBox(height: 24),
          const Text('写真を追加', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ..._existingUrls.asMap().entries.map((entry) => Stack(children: [
              GestureDetector(onTap: () => _showGalleryFromAdd(entry.key), child: Image.network(entry.value, width: 80, height: 80, fit: BoxFit.cover)),
              Positioned(right: 0, child: GestureDetector(onTap: () => setState(() => _existingUrls.remove(entry.value)), child: const Icon(Icons.cancel, color: Colors.red)))
            ])),
            ..._imageFiles.asMap().entries.map((entry) => SizedBox(width: 80, height: 80, child: GestureDetector(
              onTap: () {
                final idx = _existingUrls.length + entry.key;
                _showGalleryFromAdd(idx);
              },
              child: kIsWeb ? Image.memory(_webImageBytes[entry.key], fit: BoxFit.cover) : Image.file(File(entry.value.path), fit: BoxFit.cover),
            ))),
            GestureDetector(onTap: () async {
              final picked = await ImagePicker().pickMultiImage();
              if (picked.isNotEmpty) await _addPickedImages(picked);
            }, child: SizedBox(width: 80, height: 80, child: ColoredBox(color: Colors.grey.shade200, child: const Icon(Icons.add_a_photo, color: Colors.grey)))),
          ]),
          const SizedBox(height: 24),
          TextField(controller: _remarksController, decoration: const InputDecoration(labelText: '備考'), maxLines: 3),
          const SizedBox(height: 15),
          TextField(controller: _handoverController, decoration: const InputDecoration(labelText: '引継ぎ事項', labelStyle: TextStyle(color: Colors.redAccent)), maxLines: 3),
          const SizedBox(height: 40),
          SizedBox(width: double.infinity, height: 54, child: ElevatedButton(onPressed: _isUploading ? null : _save, style: ElevatedButton.styleFrom(backgroundColor: const Color.fromARGB(255, 255, 102, 0), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: _isUploading ? const CircularProgressIndicator(color: Colors.white) : const Text('予約内容を保存', style: TextStyle(fontWeight: FontWeight.bold)))),
          const SizedBox(height: 100),
        ])),
        if (_isUploading) Container(color: Colors.black26, child: const Center(child: CircularProgressIndicator())),
      ]),
    );
  }
}