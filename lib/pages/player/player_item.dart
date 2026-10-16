import 'package:oneanime/pages/player/player_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter_modular/flutter_modular.dart';

class PlayerItem extends StatelessWidget {
  const PlayerItem({super.key});

  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Modular.get<PlayerController>();
    return Observer(builder: (context) {
      if (playerController.dataStatus != 'loaded') {
        return const Center(child: CircularProgressIndicator());
      }
      return ValueListenableBuilder<VideoFitMode>(
        valueListenable: playerController.fitMode,
        builder: (context, mode, _) {
          return Video(
            // Video only ever copies a non-null aspectRatio over the old one,
            // so going back to the natural ratio needs a fresh state.
            key: ValueKey(mode),
            controller: playerController.videoController,
            controls: NoVideoControls,
            fit: mode.fit,
            aspectRatio: mode.aspectRatio,
            subtitleViewConfiguration: SubtitleViewConfiguration(
              style: TextStyle(
                color: Colors.pink,
                fontSize: 48.0,
                background: Paint()..color = Colors.transparent,
                decoration: TextDecoration.none,
                fontWeight: FontWeight.bold,
                shadows: const [
                  Shadow(
                    offset: Offset(1.0, 1.0),
                    blurRadius: 3.0,
                    color: Color.fromARGB(255, 255, 255, 255),
                  ),
                  Shadow(
                    offset: Offset(-1.0, -1.0),
                    blurRadius: 3.0,
                    color: Color.fromARGB(125, 255, 255, 255),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              padding: const EdgeInsets.all(24.0),
            ),
          );
        },
      );
    });
  }
}
