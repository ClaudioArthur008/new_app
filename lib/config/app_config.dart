class AppConfig {
  AppConfig._();

  static const newsApiKey = String.fromEnvironment('NEWS_API_KEY');
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
}
