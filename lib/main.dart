import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:just_audio/just_audio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cozy Music Player',
      theme: ThemeData(
        brightness: Brightness.dark,
        textTheme: GoogleFonts.merriweatherTextTheme(),
      ),
      home: MusicPlayerScreen(),
    );
  }
}

class MusicPlayerScreen extends StatefulWidget {
  @override
  _MusicPlayerScreenState createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  final AudioPlayer _player = AudioPlayer();
  final CollectionReference _firestore = FirebaseFirestore.instance.collection('music_control');
  int currentIndex = 0;
  bool isPlaying = false;
  List<String> songs = [];
  List<String> folders = [];
  String selectedFolder = '';
  int connectedDevices = 0;
  bool isConnected = false; // Track manual connection state

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isSeeking = false;

  @override
  void initState() {
    super.initState();
    _syncWithFirestore();
    _trackConnectedDevices(); // Initial fetch of device count
    _loadFolders();
    _player.positionStream.listen((position) {
      if (!_isSeeking) {
        setState(() {
          _position = position;
        });
      }
    });

    _player.durationStream.listen((duration) {
      if (duration != null) {
        setState(() {
          _duration = duration;
        });
      }
    });
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _nextSong();
      }
    });
  }
  Future<void> _loadFolders() async {
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifestMap = json.decode(manifestContent);
    final folderSet = <String>{};

    for (var path in manifestMap.keys) {
      if (path.endsWith('.mp3')) {
        final folder = path.split('/')[1];
        folderSet.add(folder);
      }
    }
    setState(() {
      folders = folderSet.toList();
    });
  }

  Future<void> _loadSongs(String folder) async {
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifestMap = json.decode(manifestContent);
    setState(() {
      currentIndex = 0; // Reset index safely
      songs = manifestMap.keys.where((path) => path.startsWith('assets/$folder') && path.endsWith('.mp3')).toList();
      selectedFolder = folder;
    });
    print("Folder: $folder, Songs Count: ${songs.length}, Current Index: $currentIndex");
    // Update Firestore with the selected folder
    await _firestore.doc('control').update({'selectedFolder': folder});
  }

  // Fetch and listen to connected devices count
  void _trackConnectedDevices() {
    // Listen to changes in the connected devices count
    _firestore.doc('devices').snapshots().listen((snapshot) {
      if (snapshot.exists) {
        setState(() {
          connectedDevices = snapshot['count'] ?? 0;
        });
      }
    });
  }

  // Manual connect
  void _connectDevice() {
    if (!isConnected) {
      _firestore.doc('devices').update({'count': FieldValue.increment(1)}); // Increase count
      setState(() {
        isConnected = true;
      });
    }
  }

  // Manual disconnect
  void _disconnectDevice() {
    if (isConnected) {
      _firestore.doc('devices').update({'count': FieldValue.increment(-1)}); // Decrease count
      setState(() {
        isConnected = false;
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _syncWithFirestore() {
    _firestore.doc('control').snapshots().listen((snapshot) {
      if (snapshot.exists) {
        var data = snapshot.data() as Map<String, dynamic>;
        setState(() {
          currentIndex = data['index'];
          isPlaying = data['isPlaying'];
        });

        if (data.containsKey('selectedFolder') && data['selectedFolder'] != selectedFolder) {
          _loadSongs(data['selectedFolder']); // Automatically update folder when changed
        }

        if (isPlaying) {
          _playSong();
        } else {
          _player.pause();
        }
      }
    });
  }
  void _onSliderChange(double value) {
    setState(() {
      _isSeeking = true;
      _position = Duration(milliseconds: value.toInt());
    });
  }

  // Add method to handle slider change end
  void _onSliderChangeEnd(double value) {
    _player.seek(Duration(milliseconds: value.toInt()));
    setState(() {
      _isSeeking = false;
    });
  }

  // Format duration to mm:ss
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  void _playSong() async {
    if (songs.isNotEmpty) {
      await _player.setAsset(songs[currentIndex]);
      _player.play();
      _firestore.doc('control').set({'index': currentIndex, 'isPlaying': true});
    }
  }

  void _pauseSong() {
    _player.pause();
    _firestore.doc('control').update({'isPlaying': false});
  }

  void _nextSong() {
    if (songs.isNotEmpty) {
      setState(() {
        currentIndex = (currentIndex + 1) % songs.length;
      });
      _playSong();
    }
  }

  void _previousSong() {
    if (songs.isNotEmpty) {
      setState(() {
        currentIndex = (currentIndex - 1 + songs.length) % songs.length;
      });
      _playSong();
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Dark background like a concert stage
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 🎸 Rock-Style Folder Selection
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: DropdownButtonFormField<String>(
                  value: selectedFolder.isNotEmpty ? selectedFolder : null,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.red[900], // Deep red for vintage feel
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  dropdownColor: Colors.orange[800], // Warm, retro color
                  style: GoogleFonts.righteous(fontSize: 18, color: Colors.white),
                  hint: Text('Choose your playlist', style: TextStyle(color: Colors.white70)),
                  items: folders.map((folder) {
                    return DropdownMenuItem<String>(
                      value: folder,
                      child: Text(folder),
                    );
                  }).toList(),
                  onChanged: (folder) {
                    if (folder != null) {
                      _loadSongs(folder);
                    }
                  },
                ),
              ),

              // 🎵 Vinyl Record Style Song Display
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Previous Song
                    if (songs.isNotEmpty)
                      Text(
                        '🔻 ${songs[(currentIndex - 1 + songs.length) % songs.length].split('/').last}',
                        style: GoogleFonts.merriweather(fontSize: 16, color: Colors.white70.withOpacity(0.6)),
                      ),
                    SizedBox(height: 5),

                    // Record Label Style Song Title
                    // Song Title Banner
                    Container(
                      padding: EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.shade700, // Retro marquee red
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.yellowAccent.withOpacity(0.6),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Text(
                        songs.isNotEmpty ? songs[currentIndex].split('/').last : 'No Song Playing',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.merriweather(
                          fontSize: 22,
                          //fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              blurRadius: 5,
                              color: Colors.black54,
                              offset: Offset(2, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 5),

                    // Next Song
                    if (songs.isNotEmpty)
                      Text(
                        '🔺 ${songs[(currentIndex + 1) % songs.length].split('/').last}',
                        style: GoogleFonts.merriweather(fontSize: 16, color: Colors.white70.withOpacity(0.6)),
                      ),

                    SizedBox(height: 20),

                    // 🎚️ Vintage Music Controls
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: Icon(Icons.skip_previous, size: 40, color: Colors.yellow[600]),
                          onPressed: _previousSong,
                        ),
                        SizedBox(width: 20),
                        ElevatedButton(
                          onPressed: isPlaying ? _pauseSong : _playSong,
                          style: ElevatedButton.styleFrom(
                            shape: CircleBorder(),
                            padding: EdgeInsets.all(25),
                            backgroundColor: Colors.orange[800],
                            shadowColor: Colors.redAccent,
                            elevation: 8,
                          ),
                          child: Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                            size: 40,
                            color: Colors.black,
                          ),
                        ),
                        SizedBox(width: 20),
                        IconButton(
                          icon: Icon(Icons.skip_next, size: 40, color: Colors.yellow[600]),
                          onPressed: _nextSong,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 🎸 Guitar Fretboard-Style Slider
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10),
                        thumbColor: Colors.yellow[700],
                        activeTrackColor: Colors.redAccent,
                        inactiveTrackColor: Colors.white12,
                        trackHeight: 6, // Looks like guitar frets
                      ),
                      child: Slider(
                        value: _position.inMilliseconds.toDouble(),
                        min: 0,
                        max: _duration.inMilliseconds.toDouble(),
                        onChanged: _onSliderChange,
                        onChangeEnd: _onSliderChangeEnd,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(_position),
                            style: TextStyle(color: Colors.white70),
                          ),
                          Text(
                            _formatDuration(_duration),
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 🎛️ Connection Settings
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Text(
                      'Connected Devices: $connectedDevices',
                      style: GoogleFonts.merriweather(fontSize: 16, color: Colors.white70),
                    ),
                    SizedBox(height: 10),
                    SwitchListTile(
                      title: Text(
                        'Manual Connection',
                        style: GoogleFonts.russoOne(fontSize: 16, color: Colors.white),
                      ),
                      value: isConnected,
                      onChanged: (bool value) {
                        if (value) {
                          _connectDevice();
                        } else {
                          _disconnectDevice();
                        }
                      },
                      activeColor: Colors.green,
                      inactiveThumbColor: Colors.red,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
