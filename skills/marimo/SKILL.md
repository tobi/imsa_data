---
name: marimo
description: Create reactive Python notebooks for IMSA racing data analysis using marimo. Use for building interactive filtering UIs (seasons, classes, events), connecting to DuckDB databases, creating reactive visualizations, and performing data analysis with automatic cell re-execution. Includes templates, patterns, and IMSA-specific workflows.
---

# Marimo Notebooks for IMSA Data Analysis

## Purpose

Create interactive, reactive marimo notebooks for analyzing IMSA racing data with:
- **Interactive filtering UIs** for seasons, classes, events, and sessions
- **Reactive programming** where cells auto-update when filters change  
- **DuckDB integration** for SQL-based data analysis
- **Visualization dashboards** with Altair charts and tables
- **Git-friendly notebooks** stored as pure Python files

## Key Concepts

### Reactive Execution
marimo automatically runs dependent cells when variables change. When you interact with a UI element (e.g., change a dropdown), all cells referencing that element automatically re-run with the new value.

```python
# Cell 1: Define UI element (global variable)
season = mo.ui.dropdown(options=[2023, 2024, 2025], value=2025)

# Cell 2: Use the value - automatically reruns when season changes
data = load_season_data(season.value)

# Cell 3: Use data - automatically reruns when data changes
chart = create_visualization(data)
```

### Critical Rules
1. **Assign UI elements to global variables** - marimo can only synchronize elements assigned to global variables
2. **Reference the `.value` attribute** - Access UI element values via `element.value`
3. **No hidden state** - Delete a cell and marimo deletes its variables
4. **Pure Python files** - Notebooks are `.py` files, not JSON

## Quick Start

### Directory

Work in ./outputs/reports folder, create it if necissary

### Installation

```bash
cd ./output/reports && uv init # if needed
cd ./output/reports && uv add marimo openai pandas ...
```

### Create New Notebook
```bash
cd ./output/reports && uv run marimo edit imsa_analysis.py
```

### Use Template
Copy the template from `assets/imsa_analysis_template.py` as a starting point for IMSA analysis.

## Building IMSA Analysis Notebooks

### Step 1: Import and Connect

```python
import marimo as mo

@app.cell
def __():
    import marimo as mo
    import duckdb
    import pandas as pd
    import altair as alt
    return alt, duckdb, mo, pd

@app.cell
def __(duckdb):
    # Connect to IMSA database
    conn = duckdb.connect("../imsa.duckdb", read_only=True)
    return conn,
```

### Step 2: Load Filter Options

```python
@app.cell
def __(conn):
    # Get available seasons, events, and classes
    seasons_df = conn.execute("""
        SELECT DISTINCT season FROM seasons 
        WHERE session = 'race'
        ORDER BY season DESC
    """).df()
    
    events_df = conn.execute("""
        SELECT DISTINCT event FROM seasons 
        WHERE session = 'race'
        ORDER BY event
    """).df()
    
    classes_df = conn.execute("""
        SELECT DISTINCT class FROM laps 
        WHERE class IS NOT NULL
        ORDER BY class
    """).df()
    
    return seasons_df, events_df, classes_df
```

### Step 3: Create Interactive Filters

```python
@app.cell
def __(mo, seasons_df, events_df, classes_df):
    # Create filter dropdowns
    season_filter = mo.ui.dropdown(
        options=seasons_df['season'].tolist(),
        value=seasons_df['season'].iloc[0],
        label="Season"
    )
    
    event_filter = mo.ui.dropdown(
        options=events_df['event'].tolist(),
        value=events_df['event'].iloc[0],
        label="Event"
    )
    
    class_filter = mo.ui.dropdown(
        options=classes_df['class'].tolist(),
        value=classes_df['class'].iloc[0],
        label="Class"
    )
    
    # Display filters horizontally
    mo.hstack([
        mo.vstack([mo.md("**Season**"), season_filter]),
        mo.vstack([mo.md("**Event**"), event_filter]),
        mo.vstack([mo.md("**Class**"), class_filter])
    ], justify="start")
    
    return season_filter, event_filter, class_filter
```

### Step 4: Get Session ID (Critical for IMSA)

```python
@app.cell
def __(conn, season_filter, event_filter, mo):
    # CRITICAL: Always work with session_id for lap time comparisons
    # Never compare lap times across different session_ids
    
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
        mo.md(f"**Session ID**: {session_id}")
    else:
        mo.md("⚠️ No race session found")
        session_id = None
    
    return session_id, session_result
```

### Step 5: Query and Analyze Data

```python
@app.cell
def __(conn, session_id, class_filter, mo):
    # Query with proper IMSA filtering
    if session_id:
        query = f"""
            SELECT 
                driver_name,
                car_number,
                lap_time,
                lap_number,
                bpillar_quartile
            FROM laps
            WHERE session_id = {session_id}
              AND class = '{class_filter.value}'
              AND bpillar_quartile IN (1, 2)  -- Top 50% clean laps
              AND flags = 'GF'  -- Green flag only
            ORDER BY lap_time
            LIMIT 100
        """
        
        laps_df = conn.execute(query).df()
        
        if len(laps_df) > 0:
            mo.md(f"Loaded {len(laps_df)} laps")
        else:
            mo.md("⚠️ No data found")
    else:
        laps_df = None
    
    return laps_df,
```

### Step 6: Visualize Results

```python
@app.cell
def __(laps_df, alt, mo):
    if laps_df is not None and len(laps_df) > 0:
        chart = alt.Chart(laps_df).mark_boxplot().encode(
            x=alt.X('driver_name:N', title='Driver', sort='-y'),
            y=alt.Y('lap_time:Q', title='Lap Time (seconds)'),
            color='driver_name:N'
        ).properties(
            width=800,
            height=400,
            title='Lap Time Distribution'
        )
        
        chart
    else:
        mo.md("No data to visualize")
    
    return chart,
```

## IMSA-Specific Requirements

### Always Use session_id
```python
# ✅ CORRECT: Filter to specific session
WHERE session_id = {session_id}
  AND class = '{class_filter.value}'

# ❌ WRONG: Comparing across sessions
WHERE season = 2025  # Don't do this for lap time analysis
```

### Always Default to Race Sessions
```python
# ✅ CORRECT: Default to 'race'
WHERE session = 'race'

# ⚠️ Only if explicitly requested
WHERE session = 'practice'  # Different objectives, not comparable
```

### Always Use BPillar Filtering for Races
```python
# ✅ CORRECT: Filter to clean, representative laps
WHERE bpillar_quartile IN (1, 2)  -- Top 50% of clean laps
  AND flags = 'GF'  -- Green flag

# ❌ WRONG: Including all laps (pit stops, traffic, etc.)
-- No quartile filtering
```

### Never Compare Across Classes
```python
# ✅ CORRECT: Analyze each class separately
WHERE session_id = {session_id} AND class = 'GTP'

# ❌ WRONG: Comparing GTP to GTD
WHERE session_id = {session_id}  -- Missing class filter
```

## Common UI Patterns

### Multi-Select for Classes
```python
class_selector = mo.ui.multiselect(
    options=["GTP", "LMP2", "GTD"],
    value=["GTP"],
    label="Select Classes"
)

# Use in query with IN clause
classes_str = "', '".join(class_selector.value)
query = f"WHERE class IN ('{classes_str}')"
```

### Slider for Top N Selection
```python
top_n = mo.ui.slider(
    start=5,
    stop=50,
    step=5,
    value=10,
    label="Top N Drivers",
    show_value=True
)

# Use in LIMIT clause
query = f"... ORDER BY lap_time LIMIT {top_n.value}"
```

### Form for Expensive Operations
```python
# Gate expensive analysis behind a form
analysis_params = mo.md("""
### Configure Analysis
- Minimum laps: {min_laps}
- Include practice: {include_practice}
""").batch(
    min_laps=mo.ui.slider(5, 50, value=10),
    include_practice=mo.ui.checkbox(value=False)
).form()

# Only run when submitted
if analysis_params.value:
    results = run_expensive_analysis(**analysis_params.value)
```

### Conditional Display with mo.stop
```python
# Stop if session not selected
mo.stop(
    session_id is None,
    mo.md("⚠️ Please select a valid session")
)

# Stop if no data
mo.stop(
    laps_df is None or len(laps_df) == 0,
    mo.md("⚠️ No data available for analysis")
)
```

## Performance Optimization

### Filter in SQL, Not Python
```python
# ✅ GOOD: Filter in SQL
query = f"""
    SELECT * FROM laps
    WHERE session_id = {session_id}
      AND class = '{class}'
      AND bpillar_quartile IN (1, 2)
    LIMIT 1000
"""
df = conn.execute(query).df()

# ❌ BAD: Load all data then filter
df = conn.execute("SELECT * FROM laps").df()
df = df[df['session_id'] == session_id]  # Inefficient
```

### Limit Data for Visualization
```python
# Sample large datasets
query = f"""
    SELECT * FROM laps
    WHERE session_id = {session_id}
    ORDER BY RANDOM()
    LIMIT 1000  -- Sample for performance
"""
```

## Visualization Patterns

### Interactive Altair Charts
```python
# Create selection
selection = alt.selection_point(fields=['driver_name'])

chart = alt.Chart(laps_df).mark_circle().encode(
    x='lap_number:Q',
    y='lap_time:Q',
    color=alt.condition(selection, 'driver_name:N', alt.value('lightgray')),
    tooltip=['driver_name', 'lap_time', 'lap_number']
).add_params(selection).properties(
    width=800,
    height=400
)
```

### Interactive Tables
```python
# Create interactive table
table = mo.ui.table(
    laps_df,
    selection='multi',  # Allow row selection
    page_size=20
)

# Display table
table

# Access selected rows in another cell
selected_rows = table.value
```

### Dashboard Layout
```python
# Create tabs for different analyses
tabs = mo.ui.tabs({
    "Lap Times": lap_time_analysis,
    "Consistency": consistency_metrics,
    "Pit Strategy": pit_analysis,
    "Weather Impact": weather_correlation
})

tabs
```

## Reference Materials

### Detailed Patterns
See `references/marimo_patterns.md` for comprehensive patterns including:
- Advanced UI element configurations
- DuckDB integration techniques
- Reactive design patterns
- Data visualization examples
- IMSA-specific query patterns
- Performance optimization tips


### Deeper docs
See `references/agent-docs.md` are officially written docs for running a marimo agent. It's excellent and you should read it. 

### Template Notebook
See `assets/imsa_analysis_template.py` for a complete working example that demonstrates:
- Database connection setup
- Interactive filter creation
- Session ID retrieval
- Proper IMSA data filtering
- Visualization and analysis
- Error handling

## Running Notebooks

### Development Mode
```bash
# Edit notebook with live preview
cd ./output/reports && uv run marimo edit notebook.py
```

### App Mode
```bash
# Run as read-only web app (hides code)
cd ./output/reports && uv run marimo run notebook.py

# Run with code visible
cd ./output/reports && uv run marimo run --include-code notebook.py

# Custom port
cd ./output/reports && uv run marimo run --port 8080 notebook.py
```

### Script Mode
```bash
# Execute notebook as Python script
cd ./output/reports && uv run python notebook.py

# With command-line arguments
cd ./output/reports && uv run python notebook.py --season 2025 --event Sebring
```

## Best Practices

### 1. One Cell, One Purpose
Each cell should have a single, clear purpose:
- Cell 1: Imports
- Cell 2: Database connection
- Cell 3: Load filter options
- Cell 4: Create UI filters
- Cell 5: Get session_id
- Cell 6: Query data
- Cell 7: Visualize

### 2. Validate Inputs
Always check if data exists before processing:
```python
if session_id and laps_df is not None and len(laps_df) > 0:
    # Process data
else:
    mo.md("⚠️ No data available")
```

### 3. Use Descriptive Variable Names
```python
# ✅ GOOD
season_filter = mo.ui.dropdown(...)
laps_df = conn.execute(query).df()

# ❌ BAD
s = mo.ui.dropdown(...)
df = conn.execute(query).df()
```

### 4. Add User Feedback
```python
# Loading indicators
with mo.status.spinner(title="Loading data..."):
    df = load_data()

# Success messages
mo.md(f"✅ Loaded {len(df)} laps")

# Warnings
if len(df) < 100:
    mo.md("⚠️ Small sample size")
```

### 5. Document Complex Queries
```python
# Add comments explaining IMSA-specific filtering
query = f"""
    SELECT * FROM laps
    WHERE session_id = {session_id}  -- Single session for comparison
      AND class = '{class}'          -- Each class analyzed separately
      AND bpillar_quartile IN (1, 2) -- Top 50% clean laps (excludes pit stops)
      AND flags = 'GF'               -- Green flag laps only
"""
```

## Troubleshooting

### UI Element Not Updating Other Cells
- **Cause**: Element not assigned to global variable
- **Fix**: Ensure `element = mo.ui.dropdown(...)` at module level

### Cell Not Re-Running on Change
- **Cause**: Cell doesn't reference the changed variable
- **Fix**: Check that cell reads `element.value` somewhere

### "No module named marimo"
- **Cause**: marimo not installed in current environment
- **Fix**: `pip install "marimo[sql]"`

### Database Connection Error
- **Cause**: Wrong path or database doesn't exist
- **Fix**: Check path in `duckdb.connect("path/to/imsa.duckdb")`

### Empty Results
- **Cause**: Filters too restrictive or no data for selection
- **Fix**: Check if session exists, validate filter values
