# IPython startup: auto-imported on every IPython/pyspark shell session

import os
import sys
import json
from pathlib import Path
from datetime import datetime, timedelta

try:
    import pandas as pd
except ImportError:
    pass

try:
    import pyspark
    from pyspark.sql import SparkSession, functions as F, types as T, Window
except ImportError:
    pass

# # Quick local SparkSession for ad-hoc testing:
# spark = SparkSession.builder \
#     .master("local[*]") \
#     .appName("adhoc") \
#     .getOrCreate()
