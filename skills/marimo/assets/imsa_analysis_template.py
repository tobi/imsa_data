"""Template marimo notebook for IMSA racing data analysis.

This template demonstrates:
- Connecting to the IMSA DuckDB database
- Creating interactive filtering UI (seasons, classes, events)
- Running data analysis on filtered data
- Visualizing results

Usage:
    marimo edit imsa_analysis_template.py
"""

import marimo

__generated_with = "0.9.0"
app = marimo.App(width="medium")


@app.cell
def __():
    import marimo as mo
    import duckdb
    import pandas as pd
    import altair as alt
    return alt, duckdb, mo, pd


@app.cell
def __(duckdb):
    # Connect to the IMSA DuckDB database
    # Adjust the path to your database location
    conn = duckdb.connect("imsa.duckdb", read_only=True)
    return conn,


@app.cell
def __(conn, mo):
    # Load available seasons, events, and classes for filtering
    seasons_df = conn.execute("""
        SELECT DISTINCT season 
        FROM seasons 
        WHERE session = 'race'
        ORDER BY season DESC
    """).df()
    
    events_df = conn.execute("""
        SELECT DISTINCT event 
        FROM seasons 
        WHERE session = 'race'
        ORDER BY event
    """).df()
    
    classes_df = conn.execute("""
        SELECT DISTINCT class 
        FROM laps 
        WHERE class IS NOT NULL
        ORDER BY class
    """).df()
    
    mo.md("""
    # IMSA Racing Data Analysis
    
    Use the filters below to select the data you want to analyze.
    """)
    return classes_df, events_df, seasons_df


@app.cell
def __(classes_df, events_df, mo, seasons_df):
    # Create interactive filter UI elements
    season_filter = mo.ui.dropdown(
        options=seasons_df['season'].tolist(),
        value=seasons_df['season'].iloc[0] if len(seasons_df) > 0 else None,
        label="Season"
    )
    
    event_filter = mo.ui.dropdown(
        options=events_df['event'].tolist(),
        value=events_df['event'].iloc[0] if len(events_df) > 0 else None,
        label="Event"
    )
    
    class_filter = mo.ui.dropdown(
        options=classes_df['class'].tolist(),
        value=classes_df['class'].iloc[0] if len(classes_df) > 0 else None,
        label="Class"
    )
    
    # Display filters in a formatted layout
    mo.hstack([
        mo.vstack([mo.md("**Season**"), season_filter]),
        mo.vstack([mo.md("**Event**"), event_filter]),
        mo.vstack([mo.md("**Class**"), class_filter])
    ], justify="start")
    return class_filter, event_filter, season_filter


@app.cell
def __(class_filter, conn, event_filter, mo, season_filter):
    # Get the session_id for the selected filters
    # This is critical - always work with session_id for lap time comparisons
    session_query = f"""
        SELECT session_id, start_date, session
        FROM seasons
        WHERE season = {season_filter.value}
          AND event = '{event_filter.value}'
          AND session = 'race'
        LIMIT 1
    """
    
    session_result = conn.execute(session_query).df()
    
    if len(session_result) > 0:
        session_id = session_result['session_id'].iloc[0]
        mo.md(f"""
        ## Selected Session
        - **Session ID**: {session_id}
        - **Season**: {season_filter.value}
        - **Event**: {event_filter.value}
        - **Class**: {class_filter.value}
        """)
    else:
        mo.md("⚠️ No race session found for the selected filters")
        session_id = None
    return session_id, session_query, session_result


@app.cell
def __(class_filter, conn, mo, session_id):
    # Query lap data with proper filtering
    # CRITICAL: Always filter to session_id + class + bpillar_quartile for race analysis
    if session_id:
        lap_query = f"""
            SELECT 
                driver_name,
                car_number,
                lap_time,
                stint_number,
                lap_number,
                flags,
                bpillar_quartile
            FROM laps
            WHERE session_id = {session_id}
              AND class = '{class_filter.value}'
              AND bpillar_quartile IN (1, 2)  -- Top 50% of clean laps
              AND flags = 'GF'  -- Green flag only
            ORDER BY lap_time
            LIMIT 100
        """
        
        laps_df = conn.execute(lap_query).df()
        
        if len(laps_df) > 0:
            mo.md(f"""
            ## Lap Data Summary
            - **Total laps analyzed**: {len(laps_df)}
            - **Unique drivers**: {laps_df['driver_name'].nunique()}
            - **Fastest lap**: {laps_df['lap_time'].min():.3f}s
            """)
        else:
            mo.md("⚠️ No lap data found for the selected filters")
    else:
        laps_df = None
        mo.md("⚠️ Select valid filters to load lap data")
    return lap_query, laps_df


@app.cell
def __(laps_df, mo):
    # Display fastest laps table
    if laps_df is not None and len(laps_df) > 0:
        fastest_laps = laps_df.groupby('driver_name').agg({
            'lap_time': 'min',
            'car_number': 'first'
        }).reset_index().sort_values('lap_time').head(10)
        
        mo.md("### Top 10 Fastest Laps")
        mo.ui.table(fastest_laps)
    else:
        mo.md("No data to display")
    return fastest_laps,


@app.cell
def __(alt, laps_df, mo):
    # Visualize lap times
    if laps_df is not None and len(laps_df) > 0:
        chart = alt.Chart(laps_df).mark_boxplot().encode(
            x=alt.X('driver_name:N', title='Driver', sort='-y'),
            y=alt.Y('lap_time:Q', title='Lap Time (seconds)'),
            color='driver_name:N'
        ).properties(
            width=800,
            height=400,
            title='Lap Time Distribution by Driver'
        )
        
        mo.md("### Lap Time Distribution")
        chart
    else:
        mo.md("No data to visualize")
    return chart,


@app.cell
def __(class_filter, conn, mo, session_id):
    # Advanced analysis: Calculate consistency metrics
    if session_id:
        consistency_query = f"""
            SELECT 
                driver_name,
                COUNT(*) as lap_count,
                AVG(lap_time) as avg_lap_time,
                STDDEV(lap_time) as std_lap_time,
                MIN(lap_time) as best_lap,
                MAX(lap_time) as worst_lap,
                (STDDEV(lap_time) / AVG(lap_time)) * 100 as coefficient_of_variation
            FROM laps
            WHERE session_id = {session_id}
              AND class = '{class_filter.value}'
              AND bpillar_quartile IN (1, 2)
              AND flags = 'GF'
            GROUP BY driver_name
            HAVING COUNT(*) >= 10
            ORDER BY coefficient_of_variation
            LIMIT 20
        """
        
        consistency_df = conn.execute(consistency_query).df()
        
        if len(consistency_df) > 0:
            mo.md("""
            ### Driver Consistency Analysis
            Lower coefficient of variation indicates more consistent lap times.
            """)
            mo.ui.table(consistency_df)
        else:
            mo.md("⚠️ Not enough data for consistency analysis")
    else:
        consistency_df = None
    return consistency_df, consistency_query


if __name__ == "__main__":
    app.run()
