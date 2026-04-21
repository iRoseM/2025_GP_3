import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home.dart' show homePage;
import 'map.dart' show mapPage;
import 'task.dart' show taskPage;
import 'levels.dart' show levelsPage;
import 'services/background_container.dart';
import 'services/bottom_nav.dart';
import 'services/connection.dart';
import 'services/title_header.dart';
import '../services/app_colors.dart';
import 'friend_profile.dart';
import 'widgets/ecoland_island.dart';
/* ======================= صفحة الأصدقاء ======================= */

class communityPage extends StatefulWidget {
  const communityPage({super.key});

  @override
  State<communityPage> createState() => _communityPageState();
}

class _communityPageState extends State<communityPage> {
  final TextEditingController _searchController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<Map<String, dynamic>> _followingList = []; // من أتابعهم
  List<Map<String, dynamic>> _followersList = []; // من يتابعونني
  bool _isLoading = false;
  bool _isSearching = false;
  String? _searchError;
  Map<String, dynamic>? _searchResult;
  int _selectedTab = 0; // 0 = أتابعهم، 1 = يتابعونني

  @override
  void initState() {
    super.initState();
    _checkConnection();
    _loadAllData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkConnection() async {
    if (!await hasInternetConnection()) {
      if (mounted) showNoInternetDialog(context);
    }
  }

  // ✅ تحميل جميع البيانات (من أتابعهم + من يتابعونني)
  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);

    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      // تحميل من أتابعهم ومن يتابعونني بالتوازي
      await Future.wait([
        _loadFollowing(currentUser.uid),
        _loadFollowers(currentUser.uid),
      ]);

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('خطأ في تحميل البيانات: $e');
      setState(() => _isLoading = false);
      _showSnackBar('حدث خطأ في تحميل البيانات', isError: true);
    }
  }

  // ✅ جلب قائمة من أتابعهم
  Future<void> _loadFollowing(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (!userDoc.exists) return;

      final List<dynamic> followingIds = userDoc.data()?['following'] ?? [];

      if (followingIds.isEmpty) {
        _followingList = [];
        return;
      }

      List<Map<String, dynamic>> following = [];

      for (String friendId in followingIds) {
        try {
          final friendDoc = await _firestore
              .collection('users')
              .doc(friendId)
              .get();

          if (friendDoc.exists) {
            final data = friendDoc.data()!;
            following.add({
              'id': friendId,
              'username': data['username'] ?? '',
              'points': data['points'] ?? 0,
              'level': _calculateLevel(data['points'] ?? 0),
              'pfpIndex': data['pfpIndex'],
            });
          }
        } catch (e) {
          debugPrint('خطأ في جلب بيانات الصديق: $e');
        }
      }

      following.sort(
        (a, b) => (b['points'] as int).compareTo(a['points'] as int),
      );
      _followingList = following;
    } catch (e) {
      debugPrint('خطأ في تحميل المتابَعين: $e');
    }
  }

  // ✅ جلب قائمة من يتابعونني
  Future<void> _loadFollowers(String userId) async {
    try {
      // البحث عن كل المستخدمين الذين لديهم userId في array الـ following
      final querySnapshot = await _firestore
          .collection('users')
          .where('following', arrayContains: userId)
          .get();

      List<Map<String, dynamic>> followers = [];

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        followers.add({
          'id': doc.id,
          'username': data['username'] ?? '',
          'points': data['points'] ?? 0,
          'level': _calculateLevel(data['points'] ?? 0),
          'pfpIndex': data['pfpIndex'],
        });
      }

      followers.sort(
        (a, b) => (b['points'] as int).compareTo(a['points'] as int),
      );
      _followersList = followers;
    } catch (e) {
      debugPrint('خطأ في تحميل المتابِعين: $e');
    }
  }

  // حساب المستوى من النقاط
  int _calculateLevel(int points) {
    if (points < 100) return 1;
    if (points < 300) return 2;
    if (points < 600) return 3;
    if (points < 1000) return 4;
    if (points < 1500) return 5;
    return 6;
  }

  // ✅ البحث عن صديق باسم المستخدم
  Future<void> _searchFriend() async {
    final username = _searchController.text.trim();

    if (username.isEmpty) {
      setState(() {
        _searchError = 'الرجاء إدخال اسم المستخدم';
        _searchResult = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = null;
      _searchResult = null;
    });

    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        setState(() {
          _searchError = 'يجب تسجيل الدخول أولاً';
          _isSearching = false;
        });
        return;
      }

      // البحث عن المستخدم
      final querySnapshot = await _firestore
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        setState(() {
          _searchError = 'اسم المستخدم غير موجود';
          _isSearching = false;
        });
        return;
      }

      final foundUser = querySnapshot.docs.first;

      // التحقق من أنه ليس المستخدم نفسه
      if (foundUser.id == currentUser.uid) {
        setState(() {
          _searchError = 'لا يمكنك إضافة نفسك كصديق';
          _isSearching = false;
        });
        return;
      }

      final userData = foundUser.data();

      setState(() {
        _searchResult = {
          'id': foundUser.id,
          'username': userData['username'] ?? '',
          'points': userData['points'] ?? 0,
          'level': _calculateLevel(userData['points'] ?? 0),
          'pfpIndex': userData['pfpIndex'],
          'completedTask': userData['completedTask'] ?? 0,
        };
        _isSearching = false;
      });
    } catch (e) {
      debugPrint('خطأ في البحث: $e');
      setState(() {
        _searchError = 'حدث خطأ أثناء البحث';
        _isSearching = false;
      });
    }
  }

  // ✅ متابعة صديق جديد
  Future<void> _followFriend(Map<String, dynamic> friend) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      _showSnackBar('يجب تسجيل الدخول أولاً', isError: true);
      return;
    }

    // التحقق من أن الصديق ليس مضافاً مسبقاً
    final isAlreadyFriend = _followingList.any((f) => f['id'] == friend['id']);

    if (isAlreadyFriend) {
      _showSnackBar('أنت تتابع هذا الصديق بالفعل', isError: true);
      return;
    }

    try {
      // إضافة الصديق إلى array في وثيقة المستخدم
      await _firestore.collection('users').doc(currentUser.uid).set({
        'following': FieldValue.arrayUnion([friend['id']]),
      }, SetOptions(merge: true));

      // تحديث القائمة المحلية
      setState(() {
        _followingList.insert(0, friend);
        _searchResult = null;
        _searchController.clear();
      });

      _showSnackBar('تمت متابعة ${friend['username']} بنجاح! 🎉');
    } catch (e) {
      debugPrint('خطأ في المتابعة: $e');
      _showSnackBar('حدث خطأ أثناء المتابعة', isError: true);
    }
  }

// ✅ إلغاء متابعة صديق
  Future<void> _unfollowFriend(String friendId, String friendName) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ✅ صورة نمير
                Image.asset(
                  'assets/img/nameerThink.png',
                  height: 120,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 16),
                // ✅ النص
                Text(
                  'هل أنت متأكد أنك تريد إلغاء متابعة $friendName؟',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: appColors.dark,
                  ),
                ),
                const SizedBox(height: 24),
                // ✅ الأزرار — تأكيد على اليسار، إلغاء على اليمين (نفس الـ logout)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: appColors.primary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(
                          'إلغاء',
                          style: GoogleFonts.ibmPlexSansArabic(
                            color: appColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: appColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(
                          'تأكيد',
                          style: GoogleFonts.ibmPlexSansArabic(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirm != true) return;

    try {
      await _firestore.collection('users').doc(currentUser.uid).update({
        'following': FieldValue.arrayRemove([friendId]),
      });

      setState(() {
        _followingList.removeWhere((f) => f['id'] == friendId);
      });

      _showSnackBar('تم إلغاء المتابعة');
    } catch (e) {
      debugPrint('خطأ في إلغاء المتابعة: $e');
      _showSnackBar('حدث خطأ', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.ibmPlexSansArabic(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        backgroundColor: isError ? appColors.red : appColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ✅ تبويب الأصدقاء = index رقم 4
  final int _currentIndex = 4;

  // ✅ دالة التنقل الموحدة بين الصفحات
  void _onTap(int i) {
    if (i == _currentIndex) return;
    switch (i) {
      case 0:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const homePage()),
        );
        break;
      case 1:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const taskPage()),
        );
        break;
      case 2:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const levelsPage()),
        );
        break;
      case 3:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const mapPage()),
        );
        break;
      case 4:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,

        // هيدر نمير العام
        appBar: const NameerAppBar(
          showTitleInBar: false,
          showBack: false,
          height: 80,
        ),

        // الخلفية المتحركة الموحدة
        body: AnimatedBackgroundContainer(
          child: Builder(
            builder: (context) {
              final statusBar = MediaQuery.of(context).padding.top;
              const headerH = 20.0;
              const gap = 12.0;
              final topPadding = statusBar + headerH + gap;

              return Padding(
                padding: EdgeInsets.fromLTRB(16, topPadding, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // العنوان
                    Text(
                      'الأصدقاء',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: appColors.dark,
                      ),
                    ),
                    const SizedBox(height: 15),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const GlobalEcoLandPage()),
                      ),
                      child: Container(
                        width: double.infinity,
                        height: 56,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF8C42), Color(0xFFFFB347)],
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF8C42).withOpacity(0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // دوائر زخرفية
                            Positioned(
                              right: -10, top: -10,
                              child: Container(
                                width: 70, height: 70,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withOpacity(0.10),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 20, bottom: -15,
                              child: Container(
                                width: 50, height: 50,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withOpacity(0.08),
                                ),
                              ),
                            ),
                            // المحتوى
                            Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.public_rounded, color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'واحة الأصدقاء',
                                    style: GoogleFonts.ibmPlexSansArabic(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // مربع البحث
                    _buildSearchSection(),

                    const SizedBox(height: 20),

                    // قائمة الأصدقاء
                    Expanded(child: _buildFriendsList()),
                  ],
                ),
              );
            },
          ),
        ),

        // شريط التنقل السفلي
        bottomNavigationBar: isKeyboardOpen
            ? null
            : BottomNavPage(currentIndex: _currentIndex, onTap: _onTap),
      ),
    );
  }

  // ✅ قسم البحث عن الأصدقاء
  Widget _buildSearchSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: appColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.person_add_rounded,
                  color: appColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'إضافة صديق جديد',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: appColors.dark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // حقل البحث
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 14,
                    color: appColors.dark,
                  ),
                  decoration: InputDecoration(
                    hintText: 'ابحث باسم المستخدم...',
                    hintStyle: GoogleFonts.ibmPlexSansArabic(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: appColors.primary,
                      size: 22,
                    ),
                    filled: true,
                    fillColor: appColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: appColors.primary.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: appColors.primary,
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  onSubmitted: (_) => _searchFriend(),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [appColors.primary, appColors.tealSoft],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: appColors.primary.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isSearching ? null : _searchFriend,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      child: _isSearching
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'بحث',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // رسالة الخطأ
          if (_searchError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: appColors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: appColors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: appColors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _searchError!,
                      style: GoogleFonts.ibmPlexSansArabic(
                        color: appColors.red,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // نتيجة البحث
          if (_searchResult != null) ...[
            const SizedBox(height: 14),
            _buildSearchResultCard(_searchResult!),
          ],
        ],
      ),
    );
  }

  // ✅ بطاقة نتيجة البحث (موزونة + زر متابعة عمودي)
  Widget _buildSearchResultCard(Map<String, dynamic> user) {
    final isAlreadyFriend = _followingList.any((f) => f['id'] == user['id']);
    final pfpIndex = user['pfpIndex'];

    return Container(
      height: 92,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            appColors.primary.withOpacity(0.08),
            appColors.mint.withOpacity(0.15),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: appColors.primary.withOpacity(0.25),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // صورة المستخدم
          _buildAvatar(pfpIndex, 28),
          const SizedBox(width: 14),

          // معلومات المستخدم
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user['username'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: appColors.dark,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildStatChip(
                      'المستوى ${user['level']}',
                      Icons.stars_rounded,
                      Colors.amber,
                    ),
                    const SizedBox(width: 8),
                    _buildStatChip(
                      '${user['points']} نقطة',
                      Icons.eco_rounded,
                      appColors.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // زر المتابعة / متابَع
          if (isAlreadyFriend)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'متابَع',
                    style: GoogleFonts.ibmPlexSansArabic(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              width: 60, // ⬅ ثابت + يمنع overflow
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [appColors.primary, appColors.tealSoft],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: appColors.primary.withOpacity(0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _followFriend(user),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.person_add_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'متابعة',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: appColors.dark,
            ),
          ),
        ],
      ),
    );
  }

  // ✅ قائمة الأصدقاء مع التبويبات
  Widget _buildFriendsList() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: appColors.primary),
            const SizedBox(height: 16),
            Text(
              'جاري تحميل الأصدقاء...',
              style: GoogleFonts.ibmPlexSansArabic(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // التبويبات
        _buildTabBar(),
        const SizedBox(height: 14),

        // المحتوى حسب التبويب المختار
        Expanded(
          child: _selectedTab == 0
              ? _buildFollowingList()
              : _buildFollowersList(),
        ),
      ],
    );
  }

  // ✅ شريط التبويبات
  Widget _buildTabBar() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              title: 'أتابعهم',
              count: _followingList.length,
              isSelected: _selectedTab == 0,
              onTap: () => setState(() => _selectedTab = 0),
            ),
          ),
          Expanded(
            child: _buildTabButton(
              title: 'يتابعونني',
              count: _followersList.length,
              isSelected: _selectedTab == 1,
              onTap: () => setState(() => _selectedTab = 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: GoogleFonts.ibmPlexSansArabic(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? appColors.primary : Colors.grey.shade600,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? appColors.primary.withOpacity(0.15)
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? appColors.primary : Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ قائمة من أتابعهم
  Widget _buildFollowingList() {
    if (_followingList.isEmpty) {
      return _buildEmptyState(
        message: 'لم تتابع أي شخص بعد',
        subMessage: 'ابحث عن أصدقائك وتابعهم!',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: appColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: _followingList.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final friend = _followingList[index];
          return _buildFriendCard(friend, index + 1, showUnfollow: true);
        },
      ),
    );
  }

  // ✅ قائمة من يتابعونني
  Widget _buildFollowersList() {
    if (_followersList.isEmpty) {
      return _buildEmptyState(
        message: 'لا يوجد متابعين بعد',
        subMessage: 'شارك اسم المستخدم الخاص بك مع أصدقائك!',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: appColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: _followersList.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final follower = _followersList[index];
          // التحقق هل أتابع هذا الشخص أيضاً
          final isFollowingBack = _followingList.any(
            (f) => f['id'] == follower['id'],
          );
          return _buildFollowerCard(follower, index + 1, isFollowingBack);
        },
      ),
    );
  }

  // ✅ الحالة الفارغة
  Widget _buildEmptyState({
    required String message,
    required String subMessage,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/img/nameerSleep.png',
            width: 140,
            height: 140,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 20),
          Text(
            message,
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: appColors.dark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subMessage,
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ✅ بناء الأفاتار
  Widget _buildAvatar(dynamic pfpIndex, double radius) {
    String? avatarPath;
    if (pfpIndex != null && pfpIndex is int && pfpIndex >= 0 && pfpIndex < 8) {
      avatarPath = 'assets/pfp/pfp${pfpIndex + 1}.png';
    }

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            appColors.primary.withOpacity(0.2),
            appColors.mint.withOpacity(0.3),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: appColors.primary.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: Colors.transparent,
        backgroundImage: avatarPath != null ? AssetImage(avatarPath) : null,
        child: avatarPath == null
            ? Icon(Icons.person_rounded, color: appColors.primary, size: radius)
            : null,
      ),
    );
  }

// ✅ بطاقة الصديق (من أتابعهم)
  Widget _buildFriendCard(
    Map<String, dynamic> friend,
    int rank, {
    bool showUnfollow = false,
  }) {
    final pfpIndex = friend['pfpIndex'];

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FriendProfilePage(
            friendId: friend['id'],
            friendUsername: friend['username'] ?? '',
            pfpIndex: pfpIndex,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // رقم الترتيب
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: rank <= 3
                    ? (rank == 1
                          ? const Color(0xFFFFD700)
                          : rank == 2
                          ? const Color(0xFFC0C0C0)
                          : const Color(0xFFCD7F32))
                    : appColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$rank',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: rank <= 3 ? Colors.white : appColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // صورة الصديق
            _buildAvatar(pfpIndex, 26),
            const SizedBox(width: 14),

            // معلومات الصديق
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    friend['username'] ?? '',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: appColors.dark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _buildFriendStat(
                        icon: Icons.stars_rounded,
                        value: 'المستوى ${friend['level']}',
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 14),
                      _buildFriendStat(
                        icon: Icons.eco_rounded,
                        value: '${friend['points']} نقطة',
                        color: appColors.primary,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // زر إلغاء المتابعة
            if (showUnfollow)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _unfollowFriend(friend['id'], friend['username']),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.person_remove_outlined,
                      color: Colors.grey.shade500,
                      size: 20,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ✅ بطاقة المتابِع (من يتابعونني)
  Widget _buildFollowerCard(
    Map<String, dynamic> follower,
    int rank,
    bool isFollowingBack,
  ) {
    final pfpIndex = follower['pfpIndex'];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // رقم الترتيب
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: rank <= 3
                  ? (rank == 1
                        ? const Color(0xFFFFD700)
                        : rank == 2
                        ? const Color(0xFFC0C0C0)
                        : const Color(0xFFCD7F32))
                  : appColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$rank',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: rank <= 3 ? Colors.white : appColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // صورة المتابع
          _buildAvatar(pfpIndex, 26),
          const SizedBox(width: 14),

          // معلومات المتابع
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      follower['username'] ?? '',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: appColors.dark,
                      ),
                    ),
                    if (isFollowingBack) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: appColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'متبادل',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: appColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _buildFriendStat(
                      icon: Icons.stars_rounded,
                      value: 'المستوى ${follower['level']}',
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 14),
                    _buildFriendStat(
                      icon: Icons.eco_rounded,
                      value: '${follower['points']} نقطة',
                      color: appColors.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // زر المتابعة إذا لم أكن أتابعه
          if (!isFollowingBack)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [appColors.primary, appColors.tealSoft],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _followFriend(follower),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      'تابع',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.check_rounded,
                color: appColors.primary,
                size: 18,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFriendStat({
    required IconData icon,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: GoogleFonts.ibmPlexSansArabic(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }
}
