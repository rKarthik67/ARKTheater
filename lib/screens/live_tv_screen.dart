import 'package:flutter/material.dart';

import '../core/responsive.dart';
import '../core/theme.dart';
import '../models/live_tv_channel.dart';
import '../models/media_item.dart';
import '../services/scraper_service.dart';
import '../video_providers/common.dart';
import '../video_providers/names.dart';
import 'player_screen.dart';

class LiveTvScreen extends StatefulWidget {
  const LiveTvScreen({super.key});

  @override
  State<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends State<LiveTvScreen> {
  late final Future<List<LiveTvChannel>> _channels = ScraperService().liveTvChannels();
  final _search = TextEditingController();
  String _query = '';
  String _language = '';
  String _category = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _play(LiveTvChannel channel) {
    final link = RegularVideoLinks(
      url: channel.url,
      server: 'Free TV',
      quality: 'Live',
      isM3U8: channel.isHls,
    );
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen(
        title: channel.name,
        mediaType: MediaType.tv,
        tmdbId: channel.id.hashCode.abs(),
        season: 1,
        episode: 1,
        providers: const [VideoProvider(fullName: 'Free TV', codeName: 'live-tv')],
        initialProviderIndex: 0,
        initialResult: ProviderLoadResult(videoLinks: [link], success: true),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LiveTvChannel>>(
      future: _channels,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Could not load live TV: ${snapshot.error}'));
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final channels = snapshot.data!;
        final languages = channels.map((item) => item.language).toSet().toList()..sort();
        final categories = channels.map((item) => item.category).toSet().toList()..sort();
        final visible = channels.where((item) {
          final query = _query.trim().toLowerCase();
          return (query.isEmpty || '${item.name} ${item.country}'.toLowerCase().contains(query)) &&
              (_language.isEmpty || item.language == _language) &&
              (_category.isEmpty || item.category == _category);
        }).toList();
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: TextField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search channels or countries'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: _filter('Language', _language, languages, (value) => setState(() => _language = value ?? ''))),
              const SizedBox(width: 12),
              Expanded(child: _filter('Category', _category, categories, (value) => setState(() => _category = value ?? ''))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Align(alignment: Alignment.centerLeft, child: Text('${visible.length} free channels · availability varies by country', style: TextStyle(color: AppTheme.textSecondaryOf(context)))),
          ),
          Expanded(child: GridView.builder(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + Responsive.bottomNavInset(context)),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 210, childAspectRatio: 1.65, crossAxisSpacing: 12, mainAxisSpacing: 12),
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final channel = visible[index];
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _play(channel),
                child: Ink(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppTheme.surfaceVariantOf(context), borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    ClipRRect(borderRadius: BorderRadius.circular(8), child: channel.logo == null ? Container(width: 44, height: 44, color: AppTheme.surfaceOf(context), alignment: Alignment.center, child: Icon(Icons.live_tv_outlined)) : Image.network(channel.logo!, width: 44, height: 44, fit: BoxFit.contain, errorBuilder: (_, __, ___) => SizedBox(width: 44, height: 44))),
                    const SizedBox(width: 10),
                    Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(channel.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)), SizedBox(height: 3), Text('${channel.country} · ${channel.language}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryOf(context))), Text(channel.category, style: TextStyle(fontSize: 12, color: AppTheme.resolvedAccent(context)))])),
                  ]),
                ),
              );
            },
          )),
        ]);
      },
    );
  }

  Widget _filter(String label, String value, List<String> values, ValueChanged<String?> onChanged) => DropdownButtonFormField<String>(
    value: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [const DropdownMenuItem(value: '', child: Text('All')), ...values.map((item) => DropdownMenuItem(value: item, child: Text(item)))],
    onChanged: onChanged,
  );
}
