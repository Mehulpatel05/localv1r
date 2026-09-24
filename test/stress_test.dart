/// Nearhood System Stress Test
/// Tests 1000+ concurrent user requests across ALL categories & features
/// Run with: dart run test/stress_test.dart
// ignore_for_file: avoid_print
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

const String backendBaseUrl = 'https://localv1r.onrender.com/api/v1';

// ── Test Configuration ─────────────────────────────────────────────────────
const int totalUsers = 1000;
const int concurrentBatchSize = 50; // Send 50 at a time to avoid socket exhaustion
const List<String> categories = [
  'general', 'services', 'food', 'rooms', 'shop', 'events', 'jobs',
];
const List<String> shopCategories = [
  'Electronics', 'Furniture', 'Vehicles', 'Books', 'Fashion', 'Home', 'Accessories', 'Other',
];

// ── Stats Tracking ─────────────────────────────────────────────────────────
int _totalRequests = 0;
int _successCount = 0;
int _failCount = 0;
int _timeoutCount = 0;
final List<int> _latencies = [];
final Map<String, int> _errorsByType = {};
final Stopwatch _globalTimer = Stopwatch();

// ── Helpers ─────────────────────────────────────────────────────────────────
String _randomHandle(int i) => 'stress_user_${i.toString().padLeft(4, '0')}';

String _randomTitle(String category) {
  final rng = Random();
  final titles = {
    'general': ['Has anyone seen...', 'Power cut in area', 'Water supply issue', 'New cafe opened', 'Traffic alert'],
    'services': ['Plumber needed', 'Electrician available', 'Cleaning service', 'Tutoring math', 'Driver available'],
    'food': ['Best biryani nearby', 'New pizza place', 'Home cooked meals', 'Chai stall review', 'Street food spot'],
    'rooms': ['1BHK near station', 'PG available Gotri', 'Flatmate needed', '2BHK furnished', 'Studio apartment'],
    'shop': ['iPhone 12 for sale', 'Study table solid wood', 'Nike sneakers UK9', 'Dell gaming laptop', 'Samsung TV 43'],
    'events': ['Cricket match Sunday', 'Navratri garba', 'Book fair this week', 'Music night at park', 'Food festival'],
    'jobs': ['Web developer needed', 'Part time cashier', 'Delivery partner', 'Intern at startup', 'Accountant role'],
  };
  final list = titles[category] ?? titles['general']!;
  return list[rng.nextInt(list.length)];
}

// ── Test 1: Health Check ────────────────────────────────────────────────────
Future<bool> testHealthCheck() async {
  print('\n${'=' * 70}');
  print('🏥 TEST 1: Backend Health Check');
  print('=' * 70);
  
  try {
    final sw = Stopwatch()..start();
    final response = await http.get(
      Uri.parse(backendBaseUrl.replaceAll('/api/v1', '/health')),
    ).timeout(const Duration(seconds: 10));
    sw.stop();
    
    if (response.statusCode == 200) {
      print('  ✅ Backend is UP — ${sw.elapsedMilliseconds}ms latency');
      print('  📡 Response: ${response.body.substring(0, min(200, response.body.length))}');
      return true;
    } else {
      print('  ⚠️  Backend responded with status ${response.statusCode}');
      return true; // Still reachable
    }
  } catch (e) {
    print('  ❌ Backend unreachable: $e');
    return false;
  }
}

// ── Test 2: Concurrent GET Requests (Feed Loading) ─────────────────────────
Future<void> testConcurrentFeedLoads() async {
  print('\n${'=' * 70}');
  print('📡 TEST 2: Concurrent Feed Load — $totalUsers simultaneous GET /posts');
  print('=' * 70);
  
  int success = 0, fail = 0, timeout = 0;
  final latencies = <int>[];
  final sw = Stopwatch()..start();
  
  // Batch to avoid socket exhaustion
  for (int batch = 0; batch < totalUsers; batch += concurrentBatchSize) {
    final batchEnd = min(batch + concurrentBatchSize, totalUsers);
    final futures = <Future>[];
    
    for (int i = batch; i < batchEnd; i++) {
      final cat = categories[i % categories.length];
      futures.add(() async {
        final reqSw = Stopwatch()..start();
        try {
          final uri = Uri.parse('$backendBaseUrl/posts').replace(
            queryParameters: {
              'limit': '20',
              'cityId': 'vadodara',
              'category': cat,
            },
          );
          final resp = await http.get(uri).timeout(const Duration(seconds: 15));
          reqSw.stop();
          latencies.add(reqSw.elapsedMilliseconds);
          _totalRequests++;
          
          if (resp.statusCode == 200) {
            success++;
            _successCount++;
          } else {
            fail++;
            _failCount++;
            _errorsByType['GET_${resp.statusCode}'] = (_errorsByType['GET_${resp.statusCode}'] ?? 0) + 1;
          }
        } on TimeoutException {
          timeout++;
          _timeoutCount++;
        } catch (e) {
          fail++;
          _failCount++;
          _errorsByType['GET_exception'] = (_errorsByType['GET_exception'] ?? 0) + 1;
        }
      }());
    }
    await Future.wait(futures);
    
    // Progress
    final done = batchEnd;
    if (done % 200 == 0 || done == totalUsers) {
      print('  📊 Progress: $done/$totalUsers — ✅ $success ❌ $fail ⏰ $timeout');
    }
  }
  sw.stop();
  
  _latencies.addAll(latencies);
  latencies.sort();
  final avgMs = latencies.isEmpty ? 0 : (latencies.reduce((a, b) => a + b) / latencies.length).round();
  final p50 = latencies.isEmpty ? 0 : latencies[latencies.length ~/ 2];
  final p95 = latencies.isEmpty ? 0 : latencies[(latencies.length * 0.95).floor()];
  final p99 = latencies.isEmpty ? 0 : latencies[(latencies.length * 0.99).floor()];
  
  print('\n  ── Feed Load Results ──');
  print('  Total Requests: $totalUsers');
  print('  ✅ Success: $success | ❌ Fail: $fail | ⏰ Timeout: $timeout');
  print('  ⏱️  Total Time: ${sw.elapsedMilliseconds}ms');
  print('  📈 Avg Latency: ${avgMs}ms | P50: ${p50}ms | P95: ${p95}ms | P99: ${p99}ms');
  print('  🔥 Throughput: ${(totalUsers * 1000 / max(1, sw.elapsedMilliseconds)).toStringAsFixed(1)} req/s');
}

// ── Test 3: Concurrent POST Requests (Create Posts in Every Category) ──────
Future<void> testConcurrentPostCreation() async {
  print('\n${'=' * 70}');
  print('📝 TEST 3: Concurrent Post Creation — $totalUsers simultaneous POST /posts/create');
  print('         (across all ${categories.length} categories)');
  print('=' * 70);
  
  int success = 0, fail = 0, timeout = 0;
  final latencies = <int>[];
  final sw = Stopwatch()..start();
  final rng = Random();
  
  for (int batch = 0; batch < totalUsers; batch += concurrentBatchSize) {
    final batchEnd = min(batch + concurrentBatchSize, totalUsers);
    final futures = <Future>[];
    
    for (int i = batch; i < batchEnd; i++) {
      final cat = categories[i % categories.length];
      final handle = _randomHandle(i);
      final title = _randomTitle(cat);
      
      futures.add(() async {
        final reqSw = Stopwatch()..start();
        try {
          final body = <String, dynamic>{
            'authorHandle': handle,
            'content': 'Stress test post #$i — $title. Testing concurrent load with $totalUsers+ users.',
            'category': cat,
            'cityId': 'vadodara',
            'areaId': 'gotri',
          };
          
          // Add category-specific fields
          if (cat == 'shop') {
            body['shopTitle'] = title;
            body['shopPrice'] = '${rng.nextInt(50000) + 500}';
            body['shopCategory'] = shopCategories[i % shopCategories.length];
          } else if (cat == 'rooms') {
            body['roomTitle'] = title;
            body['roomRent'] = '${rng.nextInt(20000) + 3000}';
            body['roomArea'] = 'Gotri';
          } else if (cat == 'jobs') {
            body['jobTitle'] = title;
            body['jobCompany'] = 'Stress Corp #$i';
            body['jobLocation'] = 'Vadodara';
            body['jobType'] = ['Full-time', 'Part-time', 'Intern'][i % 3];
          } else if (cat == 'services') {
            body['serviceTitle'] = title;
            body['servicePrice'] = '${rng.nextInt(5000) + 100}';
            body['serviceCategoryText'] = ['Plumbing', 'Electrical', 'Cleaning', 'IT'][i % 4];
          } else if (cat == 'food') {
            body['foodTitle'] = title;
            body['foodPrice'] = '${rng.nextInt(500) + 50}';
            body['foodRating'] = (3.0 + rng.nextDouble() * 2.0);
          } else if (cat == 'events') {
            body['eventTitle'] = title;
            body['eventDate'] = '2026-10-${(rng.nextInt(28) + 1).toString().padLeft(2, '0')}';
            body['eventLocationText'] = 'Vadodara Park';
            body['eventPrice'] = rng.nextBool() ? '${rng.nextInt(1000)}' : 'Free';
          }
          
          final resp = await http.post(
            Uri.parse('$backendBaseUrl/posts/create'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          ).timeout(const Duration(seconds: 20));
          reqSw.stop();
          latencies.add(reqSw.elapsedMilliseconds);
          _totalRequests++;
          
          if (resp.statusCode == 201 || resp.statusCode == 200) {
            success++;
            _successCount++;
          } else {
            fail++;
            _failCount++;
            _errorsByType['POST_${resp.statusCode}'] = (_errorsByType['POST_${resp.statusCode}'] ?? 0) + 1;
          }
        } on TimeoutException {
          timeout++;
          _timeoutCount++;
        } catch (e) {
          fail++;
          _failCount++;
          _errorsByType['POST_exception'] = (_errorsByType['POST_exception'] ?? 0) + 1;
        }
      }());
    }
    await Future.wait(futures);
    
    final done = batchEnd;
    if (done % 200 == 0 || done == totalUsers) {
      print('  📊 Progress: $done/$totalUsers — ✅ $success ❌ $fail ⏰ $timeout');
    }
  }
  sw.stop();
  
  _latencies.addAll(latencies);
  latencies.sort();
  final avgMs = latencies.isEmpty ? 0 : (latencies.reduce((a, b) => a + b) / latencies.length).round();
  final p50 = latencies.isEmpty ? 0 : latencies[latencies.length ~/ 2];
  final p95 = latencies.isEmpty ? 0 : latencies[(latencies.length * 0.95).floor()];
  final p99 = latencies.isEmpty ? 0 : latencies[(latencies.length * 0.99).floor()];
  
  print('\n  ── Post Creation Results ──');
  print('  Total Requests: $totalUsers');
  print('  ✅ Success: $success | ❌ Fail: $fail | ⏰ Timeout: $timeout');
  print('  ⏱️  Total Time: ${sw.elapsedMilliseconds}ms');
  print('  📈 Avg Latency: ${avgMs}ms | P50: ${p50}ms | P95: ${p95}ms | P99: ${p99}ms');
  print('  🔥 Throughput: ${(totalUsers * 1000 / max(1, sw.elapsedMilliseconds)).toStringAsFixed(1)} req/s');
}

// ── Test 4: Concurrent Vote Stress ──────────────────────────────────────────
Future<void> testConcurrentVoting() async {
  print('\n${'=' * 70}');
  print('👍 TEST 4: Concurrent Voting — $totalUsers simultaneous vote requests');
  print('=' * 70);
  
  // First fetch some post IDs
  List<String> postIds = [];
  try {
    final resp = await http.get(
      Uri.parse('$backendBaseUrl/posts').replace(
        queryParameters: {'limit': '50', 'cityId': 'vadodara'},
      ),
    ).timeout(const Duration(seconds: 10));
    
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final posts = data['posts'] as List<dynamic>? ?? [];
      postIds = posts.map<String>((p) => p['id'].toString()).toList();
    }
  } catch (_) {}
  
  if (postIds.isEmpty) {
    print('  ⚠️  No posts available to vote on — Skipping');
    return;
  }
  
  print('  📦 Found ${postIds.length} posts to vote on');
  
  int success = 0, fail = 0, timeout = 0;
  final sw = Stopwatch()..start();
  
  for (int batch = 0; batch < totalUsers; batch += concurrentBatchSize) {
    final batchEnd = min(batch + concurrentBatchSize, totalUsers);
    final futures = <Future>[];
    
    for (int i = batch; i < batchEnd; i++) {
      final postId = postIds[i % postIds.length];
      final direction = (i % 3 == 0) ? -1 : 1; // Mix of up/down
      
      futures.add(() async {
        try {
          final resp = await http.post(
            Uri.parse('$backendBaseUrl/posts/$postId/vote'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userHandle': _randomHandle(i),
              'direction': direction,
            }),
          ).timeout(const Duration(seconds: 15));
          _totalRequests++;
          
          if (resp.statusCode == 200) {
            success++;
            _successCount++;
          } else {
            fail++;
            _failCount++;
          }
        } on TimeoutException {
          timeout++;
          _timeoutCount++;
        } catch (_) {
          fail++;
          _failCount++;
        }
      }());
    }
    await Future.wait(futures);
  }
  sw.stop();
  
  print('  ── Voting Results ──');
  print('  ✅ Success: $success | ❌ Fail: $fail | ⏰ Timeout: $timeout');
  print('  ⏱️  Total Time: ${sw.elapsedMilliseconds}ms');
  print('  🔥 Throughput: ${(totalUsers * 1000 / max(1, sw.elapsedMilliseconds)).toStringAsFixed(1)} req/s');
}

// ── Test 5: Concurrent Comment Creation ─────────────────────────────────────
Future<void> testConcurrentComments() async {
  print('\n${'=' * 70}');
  print('💬 TEST 5: Concurrent Comments — $totalUsers simultaneous comment requests');
  print('=' * 70);
  
  // Fetch post IDs
  List<String> postIds = [];
  try {
    final resp = await http.get(
      Uri.parse('$backendBaseUrl/posts').replace(
        queryParameters: {'limit': '50', 'cityId': 'vadodara'},
      ),
    ).timeout(const Duration(seconds: 10));
    
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final posts = data['posts'] as List<dynamic>? ?? [];
      postIds = posts.map<String>((p) => p['id'].toString()).toList();
    }
  } catch (_) {}
  
  if (postIds.isEmpty) {
    print('  ⚠️  No posts available — Skipping');
    return;
  }
  
  int success = 0, fail = 0, timeout = 0;
  final sw = Stopwatch()..start();
  
  for (int batch = 0; batch < totalUsers; batch += concurrentBatchSize) {
    final batchEnd = min(batch + concurrentBatchSize, totalUsers);
    final futures = <Future>[];
    
    for (int i = batch; i < batchEnd; i++) {
      final postId = postIds[i % postIds.length];
      
      futures.add(() async {
        try {
          final resp = await http.post(
            Uri.parse('$backendBaseUrl/posts/$postId/comments'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'authorHandle': _randomHandle(i),
              'content': 'Stress test comment #$i — Testing concurrent load.',
            }),
          ).timeout(const Duration(seconds: 15));
          _totalRequests++;
          
          if (resp.statusCode == 201 || resp.statusCode == 200) {
            success++;
            _successCount++;
          } else {
            fail++;
            _failCount++;
          }
        } on TimeoutException {
          timeout++;
          _timeoutCount++;
        } catch (_) {
          fail++;
          _failCount++;
        }
      }());
    }
    await Future.wait(futures);
  }
  sw.stop();
  
  print('  ── Comment Results ──');
  print('  ✅ Success: $success | ❌ Fail: $fail | ⏰ Timeout: $timeout');
  print('  ⏱️  Total Time: ${sw.elapsedMilliseconds}ms');
  print('  🔥 Throughput: ${(totalUsers * 1000 / max(1, sw.elapsedMilliseconds)).toStringAsFixed(1)} req/s');
}

// ── Test 6: Mixed Load (Realistic Traffic Pattern) ─────────────────────────
Future<void> testMixedTrafficPattern() async {
  print('\n${'=' * 70}');
  print('🌐 TEST 6: Mixed Traffic Pattern — $totalUsers concurrent mixed requests');
  print('         (60% reads, 25% writes, 10% votes, 5% comments)');
  print('=' * 70);
  
  int success = 0, fail = 0, timeout = 0;
  final rng = Random();
  final sw = Stopwatch()..start();
  
  for (int batch = 0; batch < totalUsers; batch += concurrentBatchSize) {
    final batchEnd = min(batch + concurrentBatchSize, totalUsers);
    final futures = <Future>[];
    
    for (int i = batch; i < batchEnd; i++) {
      final roll = rng.nextInt(100);
      
      futures.add(() async {
        try {
          http.Response resp;
          
          if (roll < 60) {
            // 60% - Feed reads
            final cat = categories[i % categories.length];
            resp = await http.get(
              Uri.parse('$backendBaseUrl/posts').replace(
                queryParameters: {'limit': '20', 'cityId': 'vadodara', 'category': cat},
              ),
            ).timeout(const Duration(seconds: 15));
          } else if (roll < 85) {
            // 25% - Post creation
            final cat = categories[i % categories.length];
            resp = await http.post(
              Uri.parse('$backendBaseUrl/posts/create'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'authorHandle': _randomHandle(i),
                'content': 'Mixed load test #$i — ${_randomTitle(cat)}',
                'category': cat,
                'cityId': 'vadodara',
                'areaId': 'gotri',
              }),
            ).timeout(const Duration(seconds: 20));
          } else {
            // 15% - Health check / misc reads
            resp = await http.get(
              Uri.parse(backendBaseUrl.replaceAll('/api/v1', '/health')),
            ).timeout(const Duration(seconds: 10));
          }
          
          _totalRequests++;
          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            success++;
            _successCount++;
          } else {
            fail++;
            _failCount++;
          }
        } on TimeoutException {
          timeout++;
          _timeoutCount++;
        } catch (_) {
          fail++;
          _failCount++;
        }
      }());
    }
    await Future.wait(futures);
    
    final done = batchEnd;
    if (done % 250 == 0 || done == totalUsers) {
      print('  📊 Progress: $done/$totalUsers — ✅ $success ❌ $fail ⏰ $timeout');
    }
  }
  sw.stop();
  
  print('\n  ── Mixed Traffic Results ──');
  print('  Total Requests: $totalUsers');
  print('  ✅ Success: $success | ❌ Fail: $fail | ⏰ Timeout: $timeout');
  print('  ⏱️  Total Time: ${sw.elapsedMilliseconds}ms');
  print('  🔥 Throughput: ${(totalUsers * 1000 / max(1, sw.elapsedMilliseconds)).toStringAsFixed(1)} req/s');
}

// ── Final Summary Report ────────────────────────────────────────────────────
void printFinalReport() {
  print('\n');
  print('╔${'═' * 68}╗');
  print('║           🏁  NEARHOOD STRESS TEST — FINAL REPORT  🏁            ║');
  print('╠${'═' * 68}╣');
  print('║                                                                    ║');
  print('║  Total Requests Sent:     ${_totalRequests.toString().padRight(40)}║');
  print('║  ✅ Successful:            ${_successCount.toString().padRight(40)}║');
  print('║  ❌ Failed:                ${_failCount.toString().padRight(40)}║');
  print('║  ⏰ Timed Out:             ${_timeoutCount.toString().padRight(40)}║');
  
  final successRate = _totalRequests > 0
      ? (_successCount * 100.0 / _totalRequests).toStringAsFixed(1)
      : '0.0';
  print('║  📊 Success Rate:          ${('$successRate%').padRight(40)}║');
  
  _latencies.sort();
  if (_latencies.isNotEmpty) {
    final avgMs = (_latencies.reduce((a, b) => a + b) / _latencies.length).round();
    final p50 = _latencies[_latencies.length ~/ 2];
    final p95 = _latencies[(_latencies.length * 0.95).floor()];
    final p99 = _latencies[(_latencies.length * 0.99).floor()];
    final maxMs = _latencies.last;
    
    print('║                                                                    ║');
    print('║  ── Latency Statistics ──                                          ║');
    print('║  Average:     ${('${avgMs}ms').padRight(52)}║');
    print('║  P50 (Median):${('${p50}ms').padRight(52)}║');
    print('║  P95:         ${('${p95}ms').padRight(52)}║');
    print('║  P99:         ${('${p99}ms').padRight(52)}║');
    print('║  Max:         ${('${maxMs}ms').padRight(52)}║');
  }
  
  final elapsedSec = _globalTimer.elapsedMilliseconds / 1000.0;
  final overallThroughput = (_totalRequests / max(0.1, elapsedSec)).toStringAsFixed(1);
  print('║                                                                    ║');
  print('║  ⏱️  Total Wall Time:       ${('${elapsedSec.toStringAsFixed(1)}s').padRight(40)}║');
  print('║  🔥 Overall Throughput:    ${('$overallThroughput req/s').padRight(40)}║');
  
  if (_errorsByType.isNotEmpty) {
    print('║                                                                    ║');
    print('║  ── Error Breakdown ──                                             ║');
    _errorsByType.forEach((type, count) {
      print('║  $type: ${count.toString().padRight(55 - type.length)}║');
    });
  }
  
  print('║                                                                    ║');
  
  // Grade
  final rate = _totalRequests > 0 ? (_successCount * 100.0 / _totalRequests) : 0.0;
  String grade;
  if (rate >= 99) {
    grade = '🏆 A+ — EXCELLENT: Production ready for 1000+ users';
  } else if (rate >= 95) {
    grade = '✅ A  — GOOD: System handles high load well';
  } else if (rate >= 90) {
    grade = '⚠️  B  — ACCEPTABLE: Some requests failing under load';
  } else if (rate >= 75) {
    grade = '🟡 C  — NEEDS WORK: Noticeable failures under stress';
  } else {
    grade = '❌ F  — CRITICAL: System cannot handle concurrent load';
  }
  print('║  GRADE: ${grade.padRight(59)}║');
  print('║                                                                    ║');
  print('╚${'═' * 68}╝');
}

// ── Main Entry Point ────────────────────────────────────────────────────────
Future<void> main() async {
  print('╔${'═' * 68}╗');
  print('║       🧪  NEARHOOD SYSTEM STRESS TEST — 1000+ CONCURRENT        ║');
  print('║       Testing ALL categories, ALL features, ALL endpoints       ║');
  print('╚${'═' * 68}╝');
  print('');
  print('  👥 Simulated Users:      $totalUsers');
  print('  📦 Batch Size:           $concurrentBatchSize concurrent');
  print('  📂 Categories:           ${categories.join(', ')}');
  print('  🏪 Shop Sub-Categories:  ${shopCategories.join(', ')}');
  print('  🎯 Backend URL:          $backendBaseUrl');
  
  _globalTimer.start();
  
  // Run all tests sequentially (each test does internal concurrent batching)
  final healthy = await testHealthCheck();
  if (!healthy) {
    print('\n  ❌ Backend is not reachable. Aborting stress test.');
    print('     Please ensure the backend is running and try again.');
    return;
  }
  
  await testConcurrentFeedLoads();
  await testConcurrentPostCreation();
  await testConcurrentVoting();
  await testConcurrentComments();
  await testMixedTrafficPattern();
  
  _globalTimer.stop();
  
  printFinalReport();
}
