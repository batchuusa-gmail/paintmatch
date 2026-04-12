import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_theme.dart';
import '../models/user_project.dart';
import '../services/supabase_service.dart';
import '../utils/color_ext.dart';

class ProjectBoardScreen extends StatefulWidget {
  const ProjectBoardScreen({super.key});

  @override
  State<ProjectBoardScreen> createState() => _ProjectBoardScreenState();
}

class _ProjectBoardScreenState extends State<ProjectBoardScreen> {
  List<UserProject>? _projects;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    setState(() => _loading = true);
    try {
      final projects = await SupabaseService().getUserProjects();
      if (mounted) setState(() => _projects = projects);
    } catch (e) {
      if (mounted) setState(() => _projects = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteProject(UserProject p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Delete Project',
            style: GoogleFonts.playfairDisplay(color: AppColors.textPrimary)),
        content: Text('Delete "${p.projectName}"?',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await SupabaseService().deleteProject(p.id);
    _loadProjects();
  }

  Future<void> _renameProject(UserProject p) async {
    final controller = TextEditingController(text: p.projectName);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Rename Project',
            style: GoogleFonts.playfairDisplay(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Name',
            labelStyle: const TextStyle(color: AppColors.textSecondary),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.accent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty) return;
    await SupabaseService().renameProject(p.id, newName);
    _loadProjects();
  }

  Future<void> _signOut() async {
    await SupabaseService().signOut();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        automaticallyImplyLeading: false,
        title: Text('My Projects',
            style: GoogleFonts.playfairDisplay(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.textSecondary, size: 20),
            tooltip: 'Sign Out',
            onPressed: _signOut,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/'),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('New Room', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : (_projects == null || _projects!.isEmpty)
              ? _EmptyState(onStartNew: () => context.go('/'))
              : RefreshIndicator(
                  color: AppColors.accent,
                  onRefresh: _loadProjects,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.78,
                    ),
                    itemCount: _projects!.length,
                    itemBuilder: (_, i) => _ProjectCard(
                      project: _projects![i],
                      onDelete: () => _deleteProject(_projects![i]),
                      onRename: () => _renameProject(_projects![i]),
                      onTap: () {
                        final p = _projects![i];
                        final imageUrl = p.renderedImageUrl ?? p.roomImageUrl ?? '';
                        if (imageUrl.isEmpty) return;
                        context.push('/preview', extra: {
                          'originalImageUrl': imageUrl,
                          'renderedImageUrl': p.renderedImageUrl,
                          'selectedHex': p.selectedHex ?? '#FFFFFF',
                          'selectedColorName': p.projectName,
                          'imageFile': null,
                          'wallHex': null,
                          'vendorMatches': null,
                        });
                      },
                    ),
                  ),
                ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final UserProject project;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  const _ProjectCard({
    required this.project,
    required this.onTap,
    required this.onDelete,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final thumbnailUrl = project.renderedImageUrl ?? project.roomImageUrl;
    final swatchColor = project.selectedHex != null
        ? HexColor.fromHex(project.selectedHex!)
        : Colors.grey;

    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showActions(context),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppColors.card,
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thumbnail
            Expanded(
              child: thumbnailUrl != null
                  ? CachedNetworkImage(
                      imageUrl: thumbnailUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: AppColors.background,
                        child: const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.accent, strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.background,
                        child: const Icon(Icons.image_outlined,
                            size: 40, color: AppColors.textSecondary),
                      ),
                    )
                  : Container(
                      color: AppColors.background,
                      child: const Icon(Icons.image_outlined,
                          size: 40, color: AppColors.textSecondary),
                    ),
            ),

            // Card footer
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: swatchColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.projectName,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _formatDate(project.createdAt),
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showActions(context),
                    child: const Icon(Icons.more_vert,
                        color: AppColors.textSecondary, size: 16),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppColors.accent),
              title: const Text('Rename', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () { Navigator.pop(context); onRename(); },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () { Navigator.pop(context); onDelete(); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug',
        'Sep','Oct','Nov','Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onStartNew;
  const _EmptyState({required this.onStartNew});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.folder_open_outlined,
                  size: 36, color: AppColors.accent),
            ),
            const SizedBox(height: 20),
            Text('No projects yet',
                style: GoogleFonts.playfairDisplay(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              'Analyze a room and save it\nto see your projects here',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              icon: const Icon(Icons.add, color: Colors.black),
              label: const Text('Start New Analysis',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
              onPressed: onStartNew,
            ),
          ],
        ),
      ),
    );
  }
}
