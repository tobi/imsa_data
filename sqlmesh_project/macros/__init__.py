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
def parse_time(evaluator: MacroEvaluator, time_col: str) -> str:
    """
    Parse various time formats into decimal seconds.
    Handles formats like HH:MM:SS.mmm, MM:SS.mmm, SS.mmm
    """
    return f"""
    EXTRACT(EPOCH FROM(
        COALESCE(
            TRY_STRPTIME({time_col}, '%-H:%M:%S.%g'),
            TRY_STRPTIME('00:' || {time_col}, '%-H:%M:%S.%g'),
            TRY_STRPTIME('00:00:' || {time_col}, '%-H:%M:%S.%g'),
            TRY_STRPTIME('23:59:59', '%-H:%M:%S')
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
            STRFTIME('%H:%M:%S', MAKE_TIMESTAMP(CAST(FLOOR({time_col}) * 1000000 AS BIGINT))) ||
            '.' ||
            LPAD(CAST(CAST(ROUND(({time_col} - FLOOR({time_col})) * 1000) AS INTEGER) AS VARCHAR), 3, '0')
        ELSE
            STRFTIME('%M:%S', MAKE_TIMESTAMP(CAST(FLOOR({time_col}) * 1000000 AS BIGINT))) ||
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
    Returns the path to the data directory from config variables.
    """
    return f"'{evaluator.var('data_path')}'"


@macro()
def extract_series(evaluator: MacroEvaluator, filename_col: str) -> str:
    """Extract series_code from filename like .../imsa/2022/05-event/..."""
    return f"regexp_extract({filename_col}, '/([^/]+)/\\d{{4}}/\\d{{2}}-[^/]+/[^/]+-(?:laps|results|weather)\\.csv$', 1)"


@macro()
def extract_year(evaluator: MacroEvaluator, filename_col: str) -> str:
    """Extract year from filename."""
    return f"regexp_extract({filename_col}, '/(\\d{{4}})/\\d{{2}}-[^/]+/[^/]+-(?:laps|results|weather)\\.csv$', 1)"


@macro()
def extract_event(evaluator: MacroEvaluator, filename_col: str) -> str:
    """Extract event name from filename."""
    return f"regexp_extract({filename_col}, '/\\d{{4}}/\\d{{2}}-([^/]+)/[^/]+-(?:laps|results|weather)\\.csv$', 1)"


@macro()
def extract_timestamp(evaluator: MacroEvaluator, filename_col: str) -> str:
    """Extract timestamp from filename."""
    return f"regexp_extract({filename_col}, '/(\\d{{12}})-[^/]+-(?:laps|results|weather)\\.csv$', 1)"


@macro()
def extract_session(evaluator: MacroEvaluator, filename_col: str, file_type: str) -> str:
    """Extract session name from filename."""
    return f"regexp_extract({filename_col}, '/\\d{{12}}-([^/]+)-{file_type}\\.csv$', 1)"


@macro()
def normalize_driver_name(evaluator: MacroEvaluator, name_col: str) -> str:
    """
    Normalize a driver name for fuzzy matching:
    - Strip whitespace and normalize spaces
    - Convert to lowercase
    - Remove common diacritics (ö->o, é->e, etc.)
    - Remove suffixes like Jr., III, etc.
    """
    return f"""
    TRIM(
        REGEXP_REPLACE(
            REGEXP_REPLACE(
                LOWER(
                    TRANSLATE(
                        {name_col},
                        'ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖØòóôõöøÙÚÛÜùúûüÝýÿÑñÇç',
                        'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOOooooooUUUUuuuuYyyNnCc'
                    )
                ),
                '\\s+', ' ', 'g'
            ),
            '\\s*(jr\\.?|sr\\.?|iii|ii|iv)$', '', 'gi'
        )
    )
    """


@macro()
def driver_name_key(evaluator: MacroEvaluator, name_col: str) -> str:
    """
    Generate a sortable key from a driver name for consistent ordering.
    Extracts lastname, firstname order for sorting.
    """
    return f"""
    CASE
        WHEN {name_col} LIKE '% %' THEN
            SPLIT_PART({name_col}, ' ', -1) || ', ' ||
            REGEXP_REPLACE({name_col}, '\\s+[^\\s]+$', '')
        ELSE {name_col}
    END
    """
