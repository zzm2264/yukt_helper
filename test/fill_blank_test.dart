import 'package:flutter_test/flutter_test.dart';
import 'package:course_helper/models/presentation.dart';
import 'dart:math' as math;

int detectBlanksCount(Problem problem) {
  int detected = 1;
  final candidates = <int>[];

  // 1. 服务端 metadata 校验
  if (problem.answers.isNotEmpty) {
    candidates.add(problem.answers.length);
  }
  if (problem.options != null && problem.options!.isNotEmpty) {
    candidates.add(problem.options!.length);
  }

  final body = problem.body;
  if (body.isNotEmpty) {
    // 2. 显式填空标记: [填空1], 【填空1】, (填空1), （填空1）, [填空], 【填空】, [blank 1] 等
    final explicitPattern = RegExp(r'[\[【（\(]\s*(?:填空|空|blank)\s*(\d*)\s*[\]】）\)]', caseSensitive: false);
    final explicitMatches = explicitPattern.allMatches(body).toList();
    if (explicitMatches.isNotEmpty) {
      int maxIndex = 0;
      for (final m in explicitMatches) {
        final numStr = m.group(1);
        if (numStr != null && numStr.isNotEmpty) {
          final parsed = int.tryParse(numStr);
          if (parsed != null && parsed > maxIndex) {
            maxIndex = parsed;
          }
        }
      }
      candidates.add(math.max(explicitMatches.length, maxIndex));
    }

    // 3. 序号括号: [1], 【1】
    final bracketPattern = RegExp(r'[\[【]\s*(\d+)\s*[\]】]');
    final bracketMatches = bracketPattern.allMatches(body).toList();
    if (bracketMatches.isNotEmpty) {
      int maxIndex = 0;
      for (final m in bracketMatches) {
        final numStr = m.group(1);
        if (numStr != null && numStr.isNotEmpty) {
          final parsed = int.tryParse(numStr);
          if (parsed != null && parsed > maxIndex) {
            maxIndex = parsed;
          }
        }
      }
      candidates.add(math.max(bracketMatches.length, maxIndex));
    }

    // 4. 带圈数字: ①②③④⑤⑥⑦⑧⑨⑩...
    const circleChars = '①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳';
    int circleCount = 0;
    for (int i = 0; i < circleChars.length; i++) {
      final ch = circleChars[i];
      if (body.contains(ch)) {
        circleCount += ch.allMatches(body).length;
      }
    }
    if (circleCount > 0) {
      candidates.add(circleCount);
    }

    // 5. 下划线填空符: ___ 或 ＿＿
    final underlinePattern = RegExp(r'_{2,}|＿{2,}');
    final underlineMatches = underlinePattern.allMatches(body).toList();
    if (underlineMatches.isNotEmpty) {
      candidates.add(underlineMatches.length);
    }

    // 6. 空括号填空符: (   ) 或 （   ）
    final emptyBracketPattern = RegExp(r'\(\s{2,}\)|（\s{2,}）|\[\s{2,}\]|【\s{2,}】');
    final emptyBracketMatches = emptyBracketPattern.allMatches(body).toList();
    if (emptyBracketMatches.isNotEmpty) {
      candidates.add(emptyBracketMatches.length);
    }
  }

  if (candidates.isNotEmpty) {
    detected = candidates.reduce(math.max);
  }
  return math.max(1, detected);
}

void main() {
  group('Fill Blank Auto-Detection Tests', () {
    test('Detects full-width Chinese brackets 【填空1】...【填空5】', () {
      final problem = Problem(
        problemId: 'p1',
        problemType: 4,
        body: '这是【填空1】题，这是【填空2】题，这是【填空3】题，这是【填空4】题，这是【填空5】题',
        score: 10,
        remark: '',
        answers: [],
        hasRemark: false,
      );
      expect(detectBlanksCount(problem), 5);
    });

    test('Detects half-width ASCII brackets [填空1]...[填空3]', () {
      final problem = Problem(
        problemId: 'p2',
        problemType: 4,
        body: '填空: [填空1], [填空2], [填空3]',
        score: 10,
        remark: '',
        answers: [],
        hasRemark: false,
      );
      expect(detectBlanksCount(problem), 3);
    });

    test('Detects non-numbered brackets 【填空】 and [填空]', () {
      final problem = Problem(
        problemId: 'p3',
        problemType: 4,
        body: '填空: 【填空】和【填空】以及【填空】',
        score: 10,
        remark: '',
        answers: [],
        hasRemark: false,
      );
      expect(detectBlanksCount(problem), 3);
    });

    test('Detects circular numbers ①②③④', () {
      final problem = Problem(
        problemId: 'p4',
        problemType: 4,
        body: '请按顺序作答: ①北京 ②上海 ③广州 ④深圳',
        score: 10,
        remark: '',
        answers: [],
        hasRemark: false,
      );
      expect(detectBlanksCount(problem), 4);
    });

    test('Detects underscores and underlines ______', () {
      final problem = Problem(
        problemId: 'p5',
        problemType: 4,
        body: '光合作用需要 ______ 和 ______，生成 ______。',
        score: 10,
        remark: '',
        answers: [],
        hasRemark: false,
      );
      expect(detectBlanksCount(problem), 3);
    });

    test('Detects server metadata answers when body lacks standard markers', () {
      final problem = Problem(
        problemId: 'p6',
        problemType: 4,
        body: '这是一道复杂的题干无特殊标记题目',
        score: 10,
        remark: '',
        answers: ['ans1', 'ans2', 'ans3', 'ans4'],
        hasRemark: false,
      );
      expect(detectBlanksCount(problem), 4);
    });

    test('Falls back to at least 1 blank for empty body and metadata', () {
      final problem = Problem(
        problemId: 'p7',
        problemType: 4,
        body: '没有任何填空标记',
        score: 10,
        remark: '',
        answers: [],
        hasRemark: false,
      );
      expect(detectBlanksCount(problem), 1);
    });

    test('Takes the maximum when index numbers exceed match count (e.g. 【填空1】 and 【填空4】)', () {
      final problem = Problem(
        problemId: 'p8',
        problemType: 4,
        body: '有两空: 【填空1】与【填空4】',
        score: 10,
        remark: '',
        answers: [],
        hasRemark: false,
      );
      expect(detectBlanksCount(problem), 4);
    });
  });
}
