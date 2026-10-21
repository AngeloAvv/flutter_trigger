/// A local-first nudge engine for Flutter.
library;

// Facade
export 'src/nudge.dart';

// Conditions DSL
export 'src/dsl/event_selector.dart';
export 'src/dsl/funnel.dart'
    show
        FunnelBuilder,
        FunnelDropOffCondition,
        FunnelSessionSelector,
        FunnelTimestampSelector;
export 'src/dsl/metrics.dart' show AggregateType;
export 'src/dsl/numeric_clause.dart';
export 'src/dsl/occurrence.dart' show OccurrenceCondition, OccurrenceSelector;
export 'src/dsl/nudge_condition.dart'
    show ComparisonOperator, ConditionResult, NudgeCondition;

// Nudges
export 'src/nudges/nudge_definition.dart';

// Storage
export 'src/storage/in_memory_nudge_storage.dart';
export 'src/storage/nudge_storage.dart';
export 'src/model/event_record.dart';
export 'src/model/event_stats.dart' show EventStats;
export 'src/model/fire_record.dart';

// Widgets
export 'src/widgets/nudge_builder.dart';
export 'src/widgets/nudge_fire_listener.dart';
export 'src/widgets/nudge_listener.dart';
