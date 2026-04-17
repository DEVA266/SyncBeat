import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/room_provider.dart';
import '../utils/app_theme.dart';
import 'room_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _roomIdController = TextEditingController();
  bool _isCreating = false; // true = create mode, false = join mode
  bool _isLoading = false;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    // Listen for room join/create events
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RoomProvider>().addListener(_onRoomStateChange);
    });
  }

  void _onRoomStateChange() {
    final provider = context.read<RoomProvider>();
    if (provider.connectionState == RoomConnectionState.inRoom && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RoomScreen()),
      );
    }
    if (provider.errorMessage != null && mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage!),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _nameController.dispose();
    _roomIdController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name')),
      );
      return;
    }

    if (!_isCreating) {
      final roomId = _roomIdController.text.trim();
      if (roomId.length != 6) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Room ID must be 6 characters')),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    final provider = context.read<RoomProvider>();
    if (_isCreating) {
      provider.createRoom(name);
    } else {
      provider.joinRoom(_roomIdController.text.trim(), name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 60),
                _buildLogo(),
                const SizedBox(height: 48),
                _buildConnectionStatus(),
                const SizedBox(height: 32),
                _buildModeToggle(),
                const SizedBox(height: 24),
                _buildForm(),
                const SizedBox(height: 32),
                _buildSubmitButton(),
                const SizedBox(height: 24),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.accent, AppTheme.success],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accent.withOpacity(0.4),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.headphones_rounded, color: Colors.white, size: 40),
        ),
        const SizedBox(height: 20),
        const Text(
          'SyncBeat',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Listen together. In sync.',
          style: TextStyle(fontSize: 15, color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildConnectionStatus() {
    return Consumer<RoomProvider>(
      builder: (_, provider, __) {
        final connected = provider.isConnectedToServer;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: connected
                ? AppTheme.success.withOpacity(0.12)
                : AppTheme.danger.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: connected
                  ? AppTheme.success.withOpacity(0.4)
                  : AppTheme.danger.withOpacity(0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: connected ? AppTheme.success : AppTheme.danger,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                connected ? 'Connected to server' : 'Connecting...',
                style: TextStyle(
                  fontSize: 12,
                  color: connected ? AppTheme.success : AppTheme.danger,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          _toggleOption('Create Room', true),
          _toggleOption('Join Room', false),
        ],
      ),
    );
  }

  Widget _toggleOption(String label, bool isCreate) {
    final selected = _isCreating == isCreate;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _isCreating = isCreate),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      children: [
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Your display name',
            prefixIcon: Icon(Icons.person_outline_rounded, color: AppTheme.textSecondary),
          ),
          style: const TextStyle(color: AppTheme.textPrimary),
          textCapitalization: TextCapitalization.words,
          maxLength: 24,
        ),
        if (!_isCreating) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _roomIdController,
            decoration: const InputDecoration(
              labelText: 'Room ID (6 characters)',
              prefixIcon: Icon(Icons.tag_rounded, color: AppTheme.textSecondary),
            ),
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontFamily: 'monospace',
              letterSpacing: 4,
              fontSize: 18,
            ),
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
          ),
        ],
      ],
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accent,
          disabledBackgroundColor: AppTheme.accent.withOpacity(0.5),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Text(
                _isCreating ? 'Create Room' : 'Join Room',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
      ),
    );
  }

  Widget _buildFooter() {
    return const Text(
      'All users in the same room hear music in sync.\nNo account required.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.6),
    );
  }
}