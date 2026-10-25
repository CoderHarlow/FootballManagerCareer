import '../models/competition.dart';

abstract class FormatHandler {
  FormatType get formatType;

  /// Generates the initial round of fixtures for the stage given participants.
  List<Fixture> generateInitialFixtures({
    required String seasonCompetitionId,
    required CompetitionStage stage,
    required CompetitionRules rules,
    required List<String> teamIds,
    required DateTime seasonStartDate,
  });

  /// Recalculates standings based on played fixtures for this stage.
  List<Standing> calculateStandings({
    required String seasonCompetitionId,
    required String stageId,
    required List<String> teamIds,
    required List<Fixture> stageFixtures,
    required CompetitionRules rules,
  });

  /// Checks if all matches for the current round/stage are complete,
  /// and generates the next round of fixtures if applicable (e.g. knockout).
  List<Fixture> progressStage({
    required String seasonCompetitionId,
    required CompetitionStage stage,
    required CompetitionRules rules,
    required List<Fixture> currentFixtures,
    required DateTime lastMatchDate,
  });

  /// Returns true if the entire stage has concluded.
  bool isStageComplete(CompetitionStage stage, List<Fixture> allStageFixtures);

  /// Returns the winning team ID of the stage if completed, or null.
  String? getStageWinner(
    CompetitionStage stage,
    CompetitionRules rules,
    List<Fixture> allStageFixtures,
    List<Standing> standings,
  );
}
