"""SQLMesh macros for IMSA data transformations."""

from sqlmesh import macro
from sqlmesh.core.macros import MacroEvaluator


@macro()
def clean_event_name(evaluator: MacroEvaluator, event_name: str) -> str:
    """
    Normalize circuit names from event folder names.
    Returns a SQL CASE expression that maps event names to standardized circuit names.
    """
    return f"""
    CASE
        WHEN {event_name} ILIKE '%watkins%' OR {event_name} ILIKE '%wgi%' THEN 'Watkins Glen'
        WHEN {event_name} ILIKE '%belle-isle%' THEN 'Belle Isle'
        WHEN {event_name} ILIKE '%canadian-tire%' THEN 'Canadian Tire Motorsport Park'
        WHEN {event_name} ILIKE '%daytona%' THEN 'Daytona'
        WHEN {event_name} ILIKE '%detroit%' THEN 'Detroit'
        WHEN {event_name} ILIKE '%sebring%' THEN 'Sebring'
        WHEN {event_name} ILIKE '%indianapolis%' OR {event_name} ILIKE '%battle-on-the-bricks%' THEN 'Indianapolis'
        WHEN {event_name} ILIKE '%lime-rock%' THEN 'Lime Rock Park'
        WHEN {event_name} ILIKE '%long-beach%' THEN 'Long Beach'
        WHEN {event_name} ILIKE '%mid-ohio%' THEN 'Mid-Ohio'
        WHEN {event_name} ILIKE '%road-america%' THEN 'Road America'
        WHEN {event_name} ILIKE '%road-atlanta%' THEN 'Road Atlanta'
        WHEN {event_name} ILIKE '%roar%' THEN 'Daytona (Roar Test)'
        WHEN {event_name} ILIKE '%laguna-seca%' THEN 'Laguna Seca'
        WHEN {event_name} ILIKE '%virginia%' THEN 'Virginia International Raceway'
        WHEN {event_name} ILIKE '%february%' AND {event_name} ILIKE '%test%' THEN 'Sebring (February Test)'
        ELSE {event_name}
    END
    """


@macro()
def license_rank(evaluator: MacroEvaluator, license_col: str) -> str:
    """
    Convert license letters to numeric ranks.
    P=5 (Platinum), G=4 (Gold), S=3 (Silver), B=2 (Bronze)
    """
    return f"""
    CASE
        WHEN UPPER({license_col}[1:1]) = 'P' THEN 5
        WHEN UPPER({license_col}[1:1]) = 'G' THEN 4
        WHEN UPPER({license_col}[1:1]) = 'S' THEN 3
        WHEN UPPER({license_col}[1:1]) = 'B' THEN 2
        ELSE 0
    END
    """


@macro()
def parse_time(evaluator: MacroEvaluator, time_col: str) -> str:
    """
    Parse various time formats into decimal seconds.
    Handles formats like HH:MM:SS.mmm, MM:SS.mmm, SS.mmm
    """
    return f"""
    EXTRACT(EPOCH FROM(
        COALESCE(
            TRY_STRPTIME({time_col}, '%%-H:%%M:%%S.%%g'),
            TRY_STRPTIME('00:' || {time_col}, '%%-H:%%M:%%S.%%g'),
            TRY_STRPTIME('00:00:' || {time_col}, '%%-H:%%M:%%S.%%g'),
            TRY_STRPTIME('23:59:59', '%%-H:%%M:%%S')
        )
    )::TIME)::DECIMAL(10,3)
    """


@macro()
def format_time(evaluator: MacroEvaluator, time_col: str) -> str:
    """
    Format decimal seconds as HH:MM:SS.mmm or MM:SS.mmm
    """
    return f"""
    CASE
        WHEN {time_col} IS NULL THEN NULL
        WHEN {time_col} > 3600 THEN
            STRFTIME('%%H:%%M:%%S', MAKE_TIMESTAMP(CAST(FLOOR({time_col}) * 1000000 AS BIGINT))) ||
            '.' ||
            LPAD(CAST(CAST(ROUND(({time_col} - FLOOR({time_col})) * 1000) AS INTEGER) AS VARCHAR), 3, '0')
        ELSE
            STRFTIME('%%M:%%S', MAKE_TIMESTAMP(CAST(FLOOR({time_col}) * 1000000 AS BIGINT))) ||
            '.' ||
            LPAD(CAST(CAST(ROUND(({time_col} - FLOOR({time_col})) * 1000) AS INTEGER) AS VARCHAR), 3, '0')
    END
    """


@macro()
def format_gap(evaluator: MacroEvaluator, time_col: str) -> str:
    """
    Format gap in seconds with sign and 3 decimal places (e.g., +4.323, -1.300)
    """
    return f"""
    CASE
        WHEN {time_col} IS NULL THEN NULL
        ELSE FORMAT('{{:+.3f}}', {time_col})
    END
    """


@macro()
def data_path(evaluator: MacroEvaluator) -> str:
    """
    Returns the path to the data directory.
    """
    return "'../data'"
