import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

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
        title: const Text('Delete Project'),
        content: Text('Delete "${p.projectName}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
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
        title: const Text('Rename Project'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty) return;
    await SupabaseService().renameProject(p.id, newName);
    _loadProjects();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Projects')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/'),
        icon: const Icon(Icons.add),
        label: const Text('New Analysis'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_projects == null || _projects!.isEmpty)
              ? _EmptyState(onStartNew: () => context.go('/'))
              : RefreshIndicator(
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
                        if (p.renderedImageUrl != null) {
                          context.push('/preview', extra: {
                            'originalImageUrl': p.roomImageUrl ?? '',
                            'renderedImageUrl': p.renderedImageUrl,
                            'selectedHex': p.selectedHex ?? '#FFFFFF',
                            'selectedColorName': p.projectName,
                          });
                        }
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
          borderRadius: BorderRadius.circular(14),
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thumbnail
            Expanded(
              child: thumbnailUrl != null
                  ? CachedNetworkImage(imageUrl: thumbnailUrl, fit: BoxFit.cover)
                  : Container(color: Colors.grey[200], child: const Icon(Icons.image_outlined, size: 40, color: Colors.grey)),
            ),

            // Card footer
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  // Color swatch
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: swatchColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.projectName,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _formatDate(project.createdAt),
                          style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                        ),
                      ],
                    ),
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
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Rename'), onTap: () { Navigator.pop(context); onRename(); }),
            ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('Delete', style: TextStyle(color: Colors.red)), onTap: () { Navigator.pop(context); onDelete(); }),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onStartNew;
  const _EmptyState({required this.onStartNew});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('No projects yet', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text('Analyze a room to save your first project', style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Start New Analysis'),
            onPressed: onStartNew,
          ),
        ],
      ),
    );
  }
}
