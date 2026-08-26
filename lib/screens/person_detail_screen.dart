import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/media_item.dart';
import '../models/person_detail.dart';
import '../services/tmdb_service.dart';
import '../widgets/error_view.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/media_row.dart';

/// Cast/crew member profile: photo, bio, and every movie/TV show they've
/// worked on (tapping one opens that title's own DetailScreen via
/// `onSelectTitle`, forwarded from wherever this screen was opened from).
class PersonDetailScreen extends StatefulWidget {
  const PersonDetailScreen({
    super.key,
    required this.personId,
    required this.personName,
    required this.onSelectTitle,
  });

  final int personId;
  final String personName;
  final void Function(MediaItem) onSelectTitle;

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  final _tmdb = TmdbService();
  late Future<PersonDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = _tmdb.personDetails(widget.personId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.personName)),
      body: FutureBuilder<PersonDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingIndicator(label: 'Loading...');
          }
          if (snapshot.hasError) {
            return ErrorView(message: 'Failed to load cast details.\n${snapshot.error}');
          }
          final person = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 110,
                      height: 150,
                      child: person.profileUrl() != null
                          ? CachedNetworkImage(
                              imageUrl: person.profileUrl()!,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: AppTheme.surfaceVariant,
                              child: const Icon(
                                Icons.person_outline,
                                color: AppTheme.textSecondary,
                                size: 40,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(person.name, style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 8),
                        if (person.birthday != null)
                          Text(
                            'Born: ${person.birthday}',
                            style: const TextStyle(color: AppTheme.textSecondary),
                          ),
                        if (person.placeOfBirth != null)
                          Text(
                            person.placeOfBirth!,
                            style: const TextStyle(color: AppTheme.textSecondary),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (person.biography != null) ...[
                const SizedBox(height: 20),
                Text('Biography', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  person.biography!,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ],
              const SizedBox(height: 12),
              if (person.knownFor.isNotEmpty)
                MediaRow(
                  title: 'Known For',
                  items: person.knownFor,
                  onItemTap: widget.onSelectTitle,
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No filmography found.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
