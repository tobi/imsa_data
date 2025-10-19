# Marimo Common Patterns Reference

This document contains common patterns and best practices for building marimo notebooks, especially for data analysis with DuckDB and the IMSA database.

## Table of Contents
1. [UI Element Patterns](#ui-element-patterns)
2. [DuckDB Integration](#duckdb-integration)
3. [Reactive Design Patterns](#reactive-design-patterns)
4. [Data Visualization](#data-visualization)
5. [Performance Tips](#performance-tips)
6. [IMSA-Specific Patterns](#imsa-specific-patterns)

---

## UI Element Patterns

### Basic Dropdowns
```python
# Simple dropdown from list
seasons = mo.ui.dropdown(
    options=[2023, 2024, 2025],
    value=2025,
    label="Select Season"
)

# Dropdown from DataFrame column
events = mo.ui.dropdown(
    options=events_df['event'].tolist(),
    value=events_df['event'].iloc[0],
    label="Select Event"
)

# Dropdown with key-value pairs
class_mapping = mo.ui.dropdown(
    options={
        "GTP (Grand Touring Prototype)": "GTP",
        "LMP2 (Le Mans Prototype 2)": "LMP2",
        "GTD (Grand Touring Daytona)": "GTD"
    },
    value="GTP",
    label="Class"
)
```

### Multi-Select
```python
# Select multiple classes
classes = mo.ui.multiselect(
    options=["GTP", "LMP2", "GTD"],
    value=["GTP"],
    label="Classes to analyze"
)

# Access selected values
selected_classes = classes.value  # Returns list
```

### Sliders
```python
# Numeric range slider
lap_range = mo.ui.slider(
    start=1,
    stop=100,
    step=1,
    value=10,
    label="Top N laps",
    show_value=True
)

# Range slider for filtering
time_range = mo.ui.range_slider(
    start=0,
    stop=200,
    value=[80, 100],
    label="Lap time range (seconds)"
)
```

### Forms with Multiple Inputs
```python
# Create a form that submits all values together
filter_form = mo.md("""
### Analysis Filters

- **Season**: {season}
- **Event**: {event}
- **Class**: {class_filter}
- **Minimum laps**: {min_laps}
""").batch(
    season=mo.ui.dropdown(options=[2023, 2024, 2025]),
    event=mo.ui.dropdown(options=event_list),
    class_filter=mo.ui.dropdown(options=["GTP", "LMP2", "GTD"]),
    min_laps=mo.ui.slider(1, 50, value=10)
).form()

# Access form values after submission
if filter_form.value:
    season = filter_form.value['season']
    event = filter_form.value['event']
```

### Dynamic UI Arrays
```python
# When number of elements isn't known until runtime
# Create array of text inputs for driver names
num_drivers = driver_count.value  # From another UI element

driver_inputs = mo.ui.array([
    mo.ui.text(label=f"Driver {i+1}")
    for i in range(num_drivers)
])

# Access values
driver_names = driver_inputs.value  # Returns list of strings
```

### Conditional Display with mo.stop
```python
# Stop execution if form not submitted
mo.stop(
    filter_form.value is None,
    mo.md("⚠️ Please submit the form to continue")
)

# Stop if invalid selection
mo.stop(
    session_id is None,
    mo.md("⚠️ No session found for the selected filters")
)
```

---

## DuckDB Integration

### Connection Setup
```python
import duckdb

# Read-only connection for analysis
conn = duckdb.connect("imsa.duckdb", read_only=True)

# Or in-memory for temporary work
conn = duckdb.connect(":memory:")
```

### SQL Cells in Marimo
```python
# Method 1: Using mo.sql() for reactive SQL
result = mo.sql(
    f"""
    SELECT driver_name, MIN(lap_time) as best_lap
    FROM laps
    WHERE session_id = {session_filter.value}
      AND class = '{class_filter.value}'
    GROUP BY driver_name
    ORDER BY best_lap
    LIMIT 10
    """
)

# Access result as DataFrame
df = result.value

# Method 2: Using connection directly
query = f"""
    SELECT * FROM laps
    WHERE session_id = {session_id}
    LIMIT 100
"""
df = conn.execute(query).df()
```

### Parameterized Queries
```python
# Use Python f-strings with UI element values
query = f"""
    SELECT 
        driver_name,
        AVG(lap_time) as avg_time
    FROM laps
    WHERE session_id = {session_filter.value}
      AND class = '{class_filter.value}'
      AND bpillar_quartile IN (1, 2)
    GROUP BY driver_name
"""

# Always sanitize user inputs if accepting free-form text
# For dropdowns with predefined options, this is safe
```

---

## Reactive Design Patterns

### Cell Dependency Pattern
```python
# Cell 1: Define UI element (assigned to global variable)
season_selector = mo.ui.dropdown(options=[2023, 2024, 2025])

# Cell 2: Use the UI element's value
# This cell automatically reruns when season_selector changes
filtered_data = load_season_data(season_selector.value)

# Cell 3: Use the filtered data
# This cell automatically reruns when filtered_data changes
visualization = create_chart(filtered_data)
```

### Lazy Evaluation Pattern
```python
# For expensive computations, use forms to gate execution
analysis_form = mo.md("""
Run expensive analysis?
{confirm_button}
""").batch(
    confirm_button=mo.ui.button(label="Run Analysis")
).form()

# Only run when form is submitted
if analysis_form.value:
    expensive_result = run_expensive_analysis()
else:
    mo.md("Click button to run analysis")
```

### Caching Pattern
```python
import marimo as mo

# Cache expensive operations
@mo.cache
def load_session_data(session_id: int):
    """Expensive database operation - results cached by session_id"""
    return conn.execute(f"SELECT * FROM laps WHERE session_id = {session_id}").df()

# Use cached function
data = load_session_data(session_filter.value)
```

---

## Data Visualization

### Altair Charts
```python
import altair as alt

# Basic line chart
chart = alt.Chart(df).mark_line().encode(
    x='lap_number:Q',
    y='lap_time:Q',
    color='driver_name:N'
).properties(
    width=800,
    height=400,
    title='Lap Times Over Race Distance'
)

# Interactive selection
selection = alt.selection_point(fields=['driver_name'])

chart = alt.Chart(df).mark_circle().encode(
    x='lap_number:Q',
    y='lap_time:Q',
    color=alt.condition(selection, 'driver_name:N', alt.value('lightgray')),
    tooltip=['driver_name', 'lap_time', 'lap_number']
).add_params(selection)
```

### Display with mo.ui.altair_chart
```python
# Make chart fully interactive
chart_ui = mo.ui.altair_chart(chart)

# Access selections
selected_points = chart_ui.value
```

### Tables with mo.ui.table
```python
# Interactive table
table = mo.ui.table(
    df,
    selection='multi',  # Allow multiple row selection
    page_size=20
)

# Access selected rows
selected_data = table.value
```

---

## Performance Tips

### 1. Filter Early in SQL
```python
# ✅ Good: Filter in SQL
query = f"""
    SELECT * FROM laps
    WHERE session_id = {session_id}
      AND class = '{class_filter.value}'
      AND bpillar_quartile IN (1, 2)
    LIMIT 1000
"""
df = conn.execute(query).df()

# ❌ Bad: Load all data then filter in pandas
df = conn.execute("SELECT * FROM laps").df()
df = df[df['session_id'] == session_id]
```

### 2. Use mo.cache for Expensive Operations
```python
@mo.cache
def expensive_aggregation(session_id, class_name):
    return conn.execute(f"""
        SELECT driver_name, AVG(lap_time) as avg_time
        FROM laps
        WHERE session_id = {session_id} AND class = '{class_name}'
        GROUP BY driver_name
    """).df()

# Result is cached and only recomputes if parameters change
result = expensive_aggregation(session_filter.value, class_filter.value)
```

### 3. Limit Data for Visualization
```python
# For large datasets, sample or aggregate
query = f"""
    SELECT * FROM laps
    WHERE session_id = {session_id}
    ORDER BY RANDOM()
    LIMIT 1000  -- Sample for visualization
"""
```

### 4. Use Forms for Expensive Multi-Parameter Analysis
```python
# Prevent re-execution on every parameter change
params = mo.md("""
Configure analysis:
- Season: {season}
- Events: {events}
- Classes: {classes}
""").batch(
    season=mo.ui.dropdown(options=seasons),
    events=mo.ui.multiselect(options=all_events),
    classes=mo.ui.multiselect(options=all_classes)
).form()

# Only execute when form submitted
if params.value:
    results = run_analysis(**params.value)
```

---

## IMSA-Specific Patterns

### Session Selection Pattern
```python
# Always start by getting session_id
# NEVER compare lap times across different session_ids

# Step 1: Get available sessions
sessions_query = """
    SELECT 
        session_id,
        season,
        event,
        session,
        start_date,
        COUNT(*) as total_laps
    FROM laps
    WHERE session = 'race'
    GROUP BY session_id, season, event, session, start_date
    ORDER BY start_date DESC
"""
sessions_df = conn.execute(sessions_query).df()

# Step 2: Create session selector
session_selector = mo.ui.dropdown(
    options={
        f"{row['season']} {row['event']} - {row['session']}": row['session_id']
        for _, row in sessions_df.iterrows()
    },
    label="Select Race Session"
)

# Step 3: Use session_id in all queries
selected_session_id = session_selector.value
```

### Class-Specific Analysis Pattern
```python
# ALWAYS analyze each class separately
# Different classes have completely different performance characteristics

# Get classes for selected session
classes_query = f"""
    SELECT DISTINCT class
    FROM laps
    WHERE session_id = {session_id}
    ORDER BY class
"""
available_classes = conn.execute(classes_query).df()['class'].tolist()

# Class selector
class_selector = mo.ui.dropdown(
    options=available_classes,
    value=available_classes[0] if available_classes else None,
    label="Class"
)

# Use in queries
lap_data = conn.execute(f"""
    SELECT * FROM laps
    WHERE session_id = {session_id}
      AND class = '{class_selector.value}'
      AND bpillar_quartile IN (1, 2)
""").df()
```

### BPillar Filtering Pattern
```python
# For race analysis, ALWAYS use bpillar_quartile
# This automatically excludes pit laps, first lap, and slow laps

analysis_query = f"""
    SELECT 
        driver_name,
        AVG(lap_time) as avg_lap,
        STDDEV(lap_time) as consistency,
        COUNT(*) as lap_count
    FROM laps
    WHERE session_id = {session_id}
      AND class = '{class_name}'
      AND bpillar_quartile IN (1, 2)  -- Top 50% of clean laps
      AND flags = 'GF'  -- Green flag only
    GROUP BY driver_name
    HAVING COUNT(*) >= 10
    ORDER BY avg_lap
"""
```

### Multi-Session Comparison Pattern
```python
# When comparing across sessions, focus on relative metrics
# NEVER compare absolute lap times across different sessions

comparison_query = """
    WITH session_stats AS (
        SELECT 
            session_id,
            driver_name,
            AVG(lap_time) as driver_avg,
            MIN(lap_time) as driver_best
        FROM laps
        WHERE session_id IN ({session_ids})
          AND class = '{class_name}'
          AND bpillar_quartile IN (1, 2)
        GROUP BY session_id, driver_name
    ),
    session_leaders AS (
        SELECT 
            session_id,
            MIN(driver_avg) as session_best_avg
        FROM session_stats
        GROUP BY session_id
    )
    SELECT 
        s.session_id,
        s.driver_name,
        s.driver_avg,
        l.session_best_avg,
        ((s.driver_avg - l.session_best_avg) / l.session_best_avg * 100) as percent_off_best
    FROM session_stats s
    JOIN session_leaders l ON s.session_id = l.session_id
    ORDER BY s.session_id, percent_off_best
"""
```

### Time Formatting Pattern
```python
# Use DuckDB's interval formatting for lap times
query = f"""
    SELECT 
        driver_name,
        printf('%d:%06.3f', 
            CAST(lap_time / 60 AS INTEGER),
            lap_time - (CAST(lap_time / 60 AS INTEGER) * 60)
        ) as formatted_time,
        lap_time
    FROM laps
    WHERE session_id = {session_id}
    ORDER BY lap_time
    LIMIT 10
"""

# Or format in Python
def format_lap_time(seconds):
    """Format lap time as MM:SS.mmm"""
    minutes = int(seconds // 60)
    secs = seconds % 60
    return f"{minutes}:{secs:06.3f}"

df['formatted_time'] = df['lap_time'].apply(format_lap_time)
```

---

## Layout Tips

### Horizontal Layouts
```python
# Arrange filters horizontally
mo.hstack([
    season_filter,
    event_filter,
    class_filter
], justify="start")

# With labels
mo.hstack([
    mo.vstack([mo.md("**Season**"), season_filter]),
    mo.vstack([mo.md("**Event**"), event_filter]),
    mo.vstack([mo.md("**Class**"), class_filter])
])
```

### Vertical Layouts
```python
mo.vstack([
    mo.md("## Filters"),
    season_filter,
    event_filter,
    class_filter,
    mo.md("---"),
    mo.md("## Results"),
    results_table
])
```

### Tabs
```python
tabs = mo.ui.tabs({
    "Overview": overview_content,
    "Lap Times": lap_analysis,
    "Pit Strategy": pit_analysis,
    "Weather": weather_impact
})
tabs
```

---

## Error Handling

### Graceful Degradation
```python
# Check if data exists before visualization
if df is not None and len(df) > 0:
    chart = create_visualization(df)
    chart
else:
    mo.md("⚠️ No data available for the selected filters")

# Check for required columns
required_cols = ['driver_name', 'lap_time', 'session_id']
if all(col in df.columns for col in required_cols):
    # Process data
    pass
else:
    mo.md(f"⚠️ Missing required columns: {required_cols}")
```

### User Feedback
```python
# Loading indicator
with mo.status.spinner(title="Loading data..."):
    df = load_large_dataset()

# Progress indicator
mo.md(f"✅ Loaded {len(df)} laps from {df['driver_name'].nunique()} drivers")

# Warning messages
if len(df) < 100:
    mo.md("⚠️ Warning: Small sample size may affect analysis accuracy")
```
