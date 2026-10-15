import 'package:flutter_test/flutter_test.dart';
import 'package:course_helper/models/user.dart';
import 'package:course_helper/session/account.dart';

void main() {
  group('Account Validity & User Status Tests', () {
    test('User status defaults to true and can be modified', () {
      final user = User(
        name: '测试用户',
        avatar: '',
        phone: '13800000000',
        uid: '12345',
      );
      expect(user.status, isTrue);

      user.setStatus(false);
      expect(user.status, isFalse);

      final json = user.toJson();
      expect(json['status'], isFalse);

      final restored = User.fromJson(json);
      expect(restored.status, isFalse);
      expect(restored.uid, '12345');
    });

    test('AccountCheckResult correctly reflects validity states', () {
      final validUser = User(
        name: '有效账号',
        avatar: '',
        phone: '13800000001',
        uid: '1',
      );
      final invalidUser = User(
        name: '失效账号',
        avatar: '',
        phone: '13800000002',
        uid: '2',
        status: false,
      );

      final allValidResult = AccountCheckResult(
        totalCount: 1,
        validCount: 1,
        invalidAccounts: [],
      );
      expect(validUser.status, isTrue);
      expect(allValidResult.allValid, isTrue);
      expect(allValidResult.hasInvalid, isFalse);

      final hasInvalidResult = AccountCheckResult(
        totalCount: 2,
        validCount: 1,
        invalidAccounts: [invalidUser],
      );
      expect(hasInvalidResult.allValid, isFalse);
      expect(hasInvalidResult.hasInvalid, isTrue);
      expect(hasInvalidResult.invalidAccounts.length, 1);
      expect(hasInvalidResult.invalidAccounts.first.name, '失效账号');
    });
  });
}
