import 'package:flutter/services.dart' show appBuildName;
import 'package:oneanime/utils/constans.dart';

class Api {
  static const String domain = '${HttpString.baseUrl}/';
  static const String animeList = '${domain}animelist.json';
  static const String videoAPI = 'https://v.anime1.me/api';
  static const String version = appBuildName ?? '0.0.0';
  static const String sourceUrl = "https://github.com/Predidit/oneAnime";
  static const String bangumiSearch = "https://api.bgmapi.com/search/subject/";
  // danmaku
  static const String dandanIndex = 'https://www.dandanplay.com/';
  static const String dandanAPIDomain = 'https://api.dandanplay.net';
  static const String dandanAPIComment = "/api/v2/comment/";
  static const String dandanAPISearch = "/api/v2/search/anime";
  static const String dandanAPIBgmtv = "/api/v2/bangumi/bgmtv/";
  // 巴哈姆特動畫瘋, public and keyless
  static const String bahaSearch =
      'https://api.gamer.com.tw/mobile_app/anime/v1/search.php';
  static const String bahaVideo = 'https://api.gamer.com.tw/anime/v1/video.php';
  static const String bahaDanmu = 'https://api.gamer.com.tw/anime/v1/danmu.php';
  // github update
  static const String latestApp =
      'https://api.github.com/repos/Predidit/oneAnime/releases/latest';
}
