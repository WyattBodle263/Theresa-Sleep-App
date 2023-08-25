import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/firebase_database.dart'
    show DataSnapshot, DatabaseEvent;
import 'package:profanity_filter/profanity_filter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  late FirebaseAuth _auth;
  late DatabaseReference _userRef;
  late DatabaseReference _postsRef;
  late TextEditingController _postController;
  List<Map<String, dynamic>> _posts = [];
  bool _eulaAccepted = false; // Flag to track EULA acceptance
  final String _eulaToken = 'eulaAccepted'; // Token to store EULA acceptance
  Set<String> _blockedUsers = {}; // Set to store blocked user IDs

  @override
  void initState() {
    super.initState();
    _auth = FirebaseAuth.instance;
    _userRef = FirebaseDatabase.instance
        .ref()
        .child('users')
        .child(_auth.currentUser!.uid);
    _postsRef = FirebaseDatabase.instance.ref().child('posts');
    _postController = TextEditingController();
    _loadPosts();
    _checkEulaStatus();
    _loadBlockedUsers();
  }

  Future<void> _checkEulaStatus() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool eulaAccepted = prefs.getBool(_eulaToken) ?? false;

    setState(() {
      _eulaAccepted = eulaAccepted;
    });
  }

  Future<void> _loadPosts() async {
    final DatabaseEvent event = await _postsRef.orderByChild('timestamp').once();
    final DataSnapshot snapshot = event.snapshot;
    final dynamic postsData = snapshot.value;

    if (postsData != null) {
      final List<Map<String, dynamic>> postsList = [];
      if (postsData is Map<dynamic, dynamic>) {
        postsData.forEach((key, value) {
          final post = Map<String, dynamic>.from(value as Map).cast<String, dynamic>();
          postsList.add(post);
        });
      }

      print("Blocked Users: $_blockedUsers");

      // Filter out blocked users' posts
      final filteredPostsList = postsList.where((post) => !_blockedUsers.contains(post['userId'] as String)).toList();

      // Sort the filtered posts list
      filteredPostsList.sort((a, b) {
        final int timestampA = int.parse(a['timestamp'] as String? ?? '0');
        final int timestampB = int.parse(b['timestamp'] as String? ?? '0');
        return timestampB.compareTo(timestampA);
      });

      setState(() {
        _posts = filteredPostsList;
      });
    }
  }

  Future<void> _loadBlockedUsers() async {
    final DatabaseEvent blockedUsersEvent =
    await _userRef.child('blockedUsers').once();
    final DataSnapshot blockedUsersSnapshot = blockedUsersEvent.snapshot;
    final blockedUsersData = blockedUsersSnapshot.value;

    if (blockedUsersData != null && blockedUsersData is Map<dynamic, dynamic>) {
      final List<String> blockedUserIds =
      blockedUsersData.values.whereType<String>().toList();
      print(blockedUserIds);
      setState(() {
        _blockedUsers = Set.from(blockedUserIds);
      });
    }
  }

  @override
  void dispose() {
    _postController.dispose();
    super.dispose();
  }

  Future<void> _submitPost() async {
    final profanityFilter = ProfanityFilter();

    if (_postController.text.trim() != "" &&
        _eulaAccepted &&
        !profanityFilter.hasProfanity(_postController.text.trim())) {
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        final DateTime now = DateTime.now();
        final int timestamp = now.millisecondsSinceEpoch ~/ 1000;
        final String postKey = '${user.uid}-$timestamp';

        final DatabaseReference userRef = FirebaseDatabase.instance
            .ref()
            .child('users')
            .child(user.uid);
        final DataSnapshot userSnapshot = await userRef.get();
        final Map<dynamic, dynamic>? userData =
        userSnapshot.value as Map<dynamic, dynamic>?;

        final username = userData?['username'] as String? ?? 'anonymous';
        final avatarURL = userData?['avatarURL'] as String? ??
            'assets/profile_pictures/avatar1.png';

        final post = {
          'postKey': postKey,
          'userId': user.uid, // Make sure 'userId' is being assigned here
          'username': username,
          'avatarURL': avatarURL,
          'timestamp': timestamp.toString(),
          'text': _postController.text.trim(),
          'likes': 0,
          'likedBy': [],
        };

        setState(() {
          _posts.insert(0, post);
        });

        final DatabaseReference postRef = _postsRef.child(postKey);
        await postRef.set(post);

        _postController.clear();
      }
    }
  }

  Future<void> _submitFlag(String postKey, String postText) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      final DatabaseReference flaggedContentRef =
      FirebaseDatabase.instance.ref().child('FlagedContent');

      final DatabaseReference userRef = FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(user.uid);
      final DataSnapshot userSnapshot = await userRef.get();
      final Map<dynamic, dynamic>? userData =
      userSnapshot.value as Map<dynamic, dynamic>?;

      final username = userData?['username'] as String? ?? 'anonymous';

      final flaggedPost = {
        'username': username,
        'postText': postText,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await flaggedContentRef.child(postKey).set(flaggedPost);
    }
  }

  Future<void> _blockUser(String userId) async {
    if (!mounted) {
      return; // Widget is no longer in the tree, do not call setState
    }

    await _userRef.child('blockedUsers').push().set(userId);

    setState(() {
      _blockedUsers.add(userId);
      _loadBlockedUsers();
      _loadPosts();
    });
  }


  Future<void> _likePost(String postKey) async {
    final DatabaseReference postRef = _postsRef.child(postKey);
    final DataSnapshot postSnapshot = await postRef.get();
    final Map<dynamic, dynamic>? postData =
    postSnapshot.value as Map<dynamic, dynamic>?;

    if (postData != null) {
      final user = FirebaseAuth.instance.currentUser;
      List<dynamic> likedBy = List.from(postData['likedBy'] ?? []);

      if (user != null) {
        if (likedBy.contains(user.uid)) {
          likedBy.remove(user.uid);
        } else {
          likedBy.add(user.uid);
        }
      }

      final int currentLikes = likedBy.length;

      await postRef.update({
        'likes': currentLikes,
        'likedBy': likedBy,
      });

      setState(() {
        _posts = _posts.map((post) {
          if (post['postKey'] == postKey) {
            return {
              ...post,
              'likes': currentLikes,
              'likedBy': likedBy,
            };
          }
          return post;
        }).toList();
      });
    }
  }

  Widget _buildPostTile(Map<String, dynamic> post) {
    final username = post['username'] ?? 'anonymous';
    final avatarURL = post['avatarURL'] ?? 'assets/profile_pictures/avatar1.png';
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
        int.parse(post['timestamp'] as String? ?? '0') * 1000);

    final hour = timestamp.hour > 12 ? timestamp.hour - 12 : timestamp.hour;
    final period = timestamp.hour >= 12 ? 'PM' : 'AM';

    final formattedDate =
        '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} $hour:${timestamp.minute.toString().padLeft(2, '0')} $period';

    final user = FirebaseAuth.instance.currentUser;
    final List<dynamic> likedBy = post['likedBy'] ?? [];
    final bool isLiked = user != null && likedBy.contains(user.uid);

    bool isFlagged = false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              backgroundImage: avatarURL.startsWith('http')
                  ? NetworkImage(avatarURL)
                  : AssetImage(avatarURL) as ImageProvider<Object>?,
            ),
            const SizedBox(width: 8.0),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  formattedDate,
                  style: const TextStyle(
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8.0),
        Text(post['text'] ?? ''), // Handle potential null post['text']
        Row(
          children: [
            IconButton(
              onPressed: () => _likePost(post['postKey'] as String),
              icon: Icon(
                Icons.favorite,
                color: isLiked ? Colors.red : null,
              ),
            ),
            Text('${post['likes'] ?? 0}'),
            IconButton(
              onPressed: () {
                setState(() {
                  isFlagged = !isFlagged;
                  if (isFlagged) {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('Flagged Post'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Thank you for flagging this post. We will review this comment to determine if there is a need for further interference.',
                            ),
                            SizedBox(height: 8),
                            Text('Consider blocking this user.'),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            child: Text('OK'),
                          ),
                        ],
                      ),
                    );
                    _submitFlag(post['postKey'] as String, post['text'] as String? ?? '');
                  }
                });
              },
              icon: Icon(
                Icons.flag,
                color: isFlagged ? Colors.red : null,
              ),
            ),
            IconButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Block User'),
                    content: Text('Are you sure you want to block this user?'),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        child: Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          final userId = post['userId'] as String?;
                          print("Blocking if not null");
                          print(userId);
                          if (userId != null) {
                            print("Is not null");
                            _blockUser(userId);
                          }
                        },
                        child: Text('Block'),
                      ),
                    ],
                  ),
                );
              },
              icon: Icon(Icons.block),
            ),
          ],
        ),
        const Divider(),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    if (!_eulaAccepted) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Color(0xFFCFB1B0),
          automaticallyImplyLeading: false,
          title: Text(
            'Community',
            style: TextStyle(
              fontSize: 20.0,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              await _showEulaDialog();
            },
            child: Text('Show EULA'),
          ),
        ),
      );
    } else {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Color(0xFFCFB1B0),
          automaticallyImplyLeading: false,
          title: Text(
            'Community',
            style: TextStyle(
              fontSize: 20.0,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: ListView.builder(
                  itemCount: _posts.length,
                  itemBuilder: (context, index) {
                    final post = _posts[index];
                    return _buildPostTile(post);
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _postController,
                      decoration: const InputDecoration(
                        hintText: 'Write your post...',
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _eulaAccepted ? _submitPost : null,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _showEulaDialog() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('End User License Agreement (EULA)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('By using this app, you agree to the following terms:'),
              SizedBox(height: 10),
              Text(
                  '- No tolerance for objectionable content or abusive users.'),
              Text('- Respect and kindness towards other users.'),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                final SharedPreferences prefs =
                await SharedPreferences.getInstance();
                prefs.setBool(_eulaToken, true);
                setState(() {
                  _eulaAccepted = true;
                });
              },
              child: Text('I Agree'),
            ),
          ],
        );
      },
    );
  }
}
