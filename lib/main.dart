import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/model.dart';
import 'dart:io' show Platform;

void main() {
  runApp(const GemmaApp());
}

class GemmaApp extends StatelessWidget {
  const GemmaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Gemma GGUF Chat',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const GemmaHomePage(),
    );
  }
}

class GemmaHomePage extends StatefulWidget {
  const GemmaHomePage({super.key});

  @override
  State<GemmaHomePage> createState() => _GemmaHomePageState();
}

class _GemmaHomePageState extends State<GemmaHomePage> {
  final TextEditingController _textController = TextEditingController();
  final List<String> _messages = [];

  InferenceModel? _model;
  InferenceChat? _chat; // Changed from Conversation to InferenceChat
  bool _isLoadingModel = false;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  Future<void> _initializeModel() async {
    setState(() => _isLoadingModel = true);
    
    try {
      // Log platform information for debugging
      print('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
      
      // Check if we're running on a supported platform (Android or iOS)
      if (!Platform.isAndroid && !Platform.isIOS) {
        throw Exception('Platform not supported. Flutter Gemma plugin currently only supports Android and iOS.');
      }
      
      final gemma = FlutterGemmaPlugin.instance;
      final modelManager = gemma.modelManager;

      // Check plugin initialization
      print('Plugin instance: $gemma');
      print('Model manager: $modelManager');
      
      // Verify model URL is accessible
      const modelUrl = 'https://huggingface.co/unsloth/gemma-3-270m-it-GGUF/resolve/main/gemma-3-270m-it-IQ4_NL.gguf';
      print('Attempting to download model from: $modelUrl');
      
      // Download GGUF model from network and install it once
      await modelManager.downloadModelFromNetwork(modelUrl);
      print('Model downloaded successfully');
      
      // Create the model instance with more explicit parameters and error handling
      print('Creating model instance...');
      _model = await gemma.createModel(
        modelType: ModelType.gemmaIt,
        maxTokens: 512,
        // Remove the PreferredBackend parameter since it's causing issues
        // preferredBackend: PreferredBackend.cpu,
      );
      print('Model instance created: $_model');
      
      // Create conversation chat instance
      _chat = await _model!.createChat();
      print('Chat instance created: $_chat');

      setState(() {
        _isLoadingModel = false;
      });
    } catch (e, stackTrace) {
      setState(() => _isLoadingModel = false);
      print('Model initialization error: $e');
      print('Stack trace: $stackTrace');
      _showSnackBar('Failed to load model: ${e.toString()}');
    }
  }

  Future<void> _sendMessage() async {
    if (_textController.text.isEmpty || _isGenerating || _chat == null) return;

    final userMessage = _textController.text.trim();
    setState(() {
      _messages.add('You: $userMessage');
      _textController.clear();
      _isGenerating = true;
    });

    try {
      await _chat!.addQueryChunk(Message.text(text: userMessage, isUser: true));

      // Generate response from model (async streaming is also possible)
      ModelResponse response = await _chat!.generateChatResponse();

      if (response is TextResponse) {
        setState(() {
          _messages.add('Gemma: ${response.token}');
          _isGenerating = false;
        });
      } else {
        setState(() {
          _messages.add('Gemma: [Unsupported response type]');
          _isGenerating = false;
        });
      }
    } catch (e) {
      setState(() {
        _messages.add('Error: $e');
        _isGenerating = false;
      });
    }
  }

  void _showSnackBar(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    
    try {
      // Close resources safely with null checks
      if (_chat?.session != null) {
        _chat!.session.close();
      }
      
      if (_model != null) {
        _model!.close();
      }
    } catch (e) {
      print('Error during resource cleanup: $e');
    }
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Gemma GGUF Chat'),
      ),
      body: _isLoadingModel
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading Gemma model...'),
                  Text('This may take a while on first run'),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isUser = message.startsWith('You:');
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isUser ? Colors.blue.shade100 : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            message,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_isGenerating) const LinearProgressIndicator(),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          enabled: !_isGenerating,
                          decoration: const InputDecoration(
                            hintText: 'Type your message',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _isGenerating ? null : _sendMessage,
                      ),
                    ],
                  ),
                )
              ],
            ),
    );
  }
}
