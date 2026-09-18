import 'package:flutter_test/flutter_test.dart';
import 'package:its_app/domain/models.dart';

void main() {
  test('Idea status database mapping is stable', () {
    expect(IdeaStatusX.fromDb('Ready'), IdeaStatus.ready);
    expect(IdeaStatus.shelved.dbValue, 'Shelved');
    expect(IdeaStatus.newIdea.label, '新想法');
  });

  test('Task status database mapping is stable', () {
    expect(TaskStatusX.fromDb('Doing'), TaskStatus.doing);
    expect(TaskStatus.done.dbValue, 'Done');
  });
}
