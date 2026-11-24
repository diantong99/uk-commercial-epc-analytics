
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

from pathlib import Path
from sklearn.preprocessing import StandardScaler
from sklearn.cluster import MiniBatchKMeans

# =====================================================
# 1. Read CSV
# =====================================================

# Repository layout: python/epc_kmeans.py, data/ml_features_with_date.csv
PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = PROJECT_ROOT / "data"
OUTPUT_DIR = PROJECT_ROOT / "outputs"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

df = pd.read_csv(
    DATA_DIR / "ml_features_with_date.csv",
    low_memory=False
)

df["lodgement_date"] = pd.to_datetime(
    df["lodgement_date"],
    errors="coerce"
)

df["year"] = df["lodgement_date"].dt.year

print("Total rows:", len(df))
print("\nYear distribution:")
print(df["year"].value_counts(dropna=False).sort_index())


# =====================================================
# 2. Train / Test split by time
# =====================================================

train = df[df["year"].between(2021, 2024)].copy()
test = df[df["year"].between(2025, 2026)].copy()

print("\nTraining records:", len(train))
print("Test records:", len(test))
print("Excluded records:", len(df) - len(train) - len(test))

if train.empty or test.empty:
    raise ValueError("Training or test set is empty. Check dates.")


# =====================================================
# 3. Feature preprocessing
# =====================================================

# Calculate OTHER ratio
for data in (train, test):
    data["other_ratio"] = np.where(
        data["total_recommendations"] > 0,
        data["other_count"] / data["total_recommendations"],
        0.0
    )

    data["has_recommendations"] = (
        data["total_recommendations"] > 0
    ).astype(int)

    ratio_cols = [
        "short_ratio",
        "medium_ratio",
        "long_ratio"
    ]

    no_rec = data["total_recommendations"] == 0

    data.loc[no_rec, ratio_cols] = (
        data.loc[no_rec, ratio_cols].fillna(0)
    )

    data["log_total_recommendations"] = np.log1p(
        data["total_recommendations"]
    )

# Six model features
features = [
    "epc_rating_score",
    "log_total_recommendations",
    "short_ratio",
    "medium_ratio",
    "long_ratio",
    "other_ratio"
]

# Check values
for data in (train, test):
    if not np.isfinite(
        data[features].to_numpy(dtype=float)
    ).all():
        raise ValueError("Missing or invalid feature values.")


# =====================================================
# 4. Standardization
# Fit on TRAIN only
# =====================================================

scaler = StandardScaler()

X_train = scaler.fit_transform(train[features])
X_test = scaler.transform(test[features])


# =====================================================
# 5. Train K-Means on 2021-2024
# =====================================================

model = MiniBatchKMeans(
    n_clusters=4,
    random_state=42,
    batch_size=4096,
    n_init=10,
    max_iter=200
)

train["cluster"] = model.fit_predict(X_train)

# Do NOT refit on test data
test["cluster"] = model.predict(X_test)


# =====================================================
# 6. Compare cluster distributions
# =====================================================

train_pct = (
    train["cluster"]
    .value_counts(normalize=True)
    .reindex(range(4), fill_value=0)
    * 100
)

test_pct = (
    test["cluster"]
    .value_counts(normalize=True)
    .reindex(range(4), fill_value=0)
    * 100
)

comparison = pd.DataFrame({
    "train_percentage": train_pct,
    "test_percentage": test_pct
})

comparison["difference_pp"] = (
    comparison["test_percentage"]
    - comparison["train_percentage"]
)

print("\n========== CLUSTER DISTRIBUTION ==========")
print(comparison.round(2))


# =====================================================
# 7. Cluster profiles in train and test
# =====================================================

def get_profile(data):
    return data.groupby("cluster").agg(
        certificates=("certificate_number", "count"),
        avg_epc_rating=("epc_rating_score", "mean"),
        avg_recommendations=("total_recommendations", "mean"),
        avg_short_ratio=("short_ratio", "mean"),
        avg_medium_ratio=("medium_ratio", "mean"),
        avg_long_ratio=("long_ratio", "mean"),
        avg_other_ratio=("other_ratio", "mean"),
        pct_without_recommendations=(
            "has_recommendations",
            lambda s: (1 - s.mean()) * 100
        )
    ).round(3)


train_profile = get_profile(train)
test_profile = get_profile(test)

print("\n========== TRAIN PROFILE ==========")
print(train_profile)

print("\n========== TEST PROFILE ==========")
print(test_profile)


# =====================================================
# 8. Distance to assigned cluster centers
# =====================================================

def nearest_distance(X, model):
    centers = model.cluster_centers_
    labels = model.predict(X)

    return np.linalg.norm(
        X - centers[labels],
        axis=1
    )


train["center_distance"] = nearest_distance(
    X_train, model
)

test["center_distance"] = nearest_distance(
    X_test, model
)

# Threshold based on training distances
threshold = np.quantile(
    train["center_distance"], 0.95
)

print("\n========== DISTANCE CHECK ==========")
print(
    "Train mean distance:",
    round(train["center_distance"].mean(), 3)
)
print(
    "Test mean distance:",
    round(test["center_distance"].mean(), 3)
)
print(
    "Train 95th percentile threshold:",
    round(threshold, 3)
)
print(
    "Test above train threshold (%):",
    round(
        (test["center_distance"] > threshold).mean() * 100,
        2
    )
)


# =====================================================
# 9. Plot cluster distribution
# =====================================================

ax = comparison[
    ["train_percentage", "test_percentage"]
].plot(kind="bar", figsize=(9, 5))

ax.set_xlabel("Cluster")
ax.set_ylabel("Percentage (%)")
ax.set_title("Cluster Distribution: Train vs Test")
ax.legend(["2021-2024", "2025-2026"])

plt.tight_layout()
plt.savefig(
    OUTPUT_DIR / "cluster_time_comparison.png",
    dpi=200
)
plt.show()


# =====================================================
# 10. Export results
# =====================================================

comparison.to_csv(
    OUTPUT_DIR / "cluster_time_distribution_6features.csv",
    encoding="utf-8-sig"
)

train_profile.to_csv(
    OUTPUT_DIR / "cluster_train_profile_6features.csv",
    encoding="utf-8-sig"
)

test_profile.to_csv(
    OUTPUT_DIR / "cluster_test_profile_6features.csv",
    encoding="utf-8-sig"
)

train.to_csv(
    OUTPUT_DIR / "epc_train_clusters_6features.csv",
    index=False,
    encoding="utf-8-sig"
)

test.to_csv(
    OUTPUT_DIR / "epc_test_clusters_6features.csv",
    index=False,
    encoding="utf-8-sig"
)



# =====================================================
# 11. EPC Rating Distribution by Cluster
# =====================================================

ratings = ["A", "B", "C", "D", "E", "F", "G"]

def calculate_rating_distribution(data):

    # Count certificates by cluster and EPC rating
    counts = pd.crosstab(
        data["cluster"],
        data["epc_rating"]
    ).reindex(
        index=range(4),
        columns=ratings,
        fill_value=0
    )

    # Calculate percentage within each cluster
    percentages = counts.div(
        counts.sum(axis=1).replace(0, np.nan),
        axis=0
    ) * 100

    percentages = percentages.fillna(0)

    # Calculate D-G and F/G percentages
    percentages["D_G_percentage"] = (
        percentages[["D", "E", "F", "G"]].sum(axis=1)
    )

    percentages["F_G_percentage"] = (
        percentages[["F", "G"]].sum(axis=1)
    )

    # Add certificate counts
    percentages.insert(
        0,
        "certificates",
        counts.sum(axis=1)
    )

    return percentages.round(2)


# Combine training and test records
all_data = pd.concat(
    [train, test],
    ignore_index=True
)

# Calculate rating distributions
train_distribution = calculate_rating_distribution(train)
test_distribution = calculate_rating_distribution(test)
all_distribution = calculate_rating_distribution(all_data)

print("\n========== TRAIN EPC DISTRIBUTION ==========")
print(train_distribution.to_string())

print("\n========== TEST EPC DISTRIBUTION ==========")
print(test_distribution.to_string())

print("\n========== ALL EPC DISTRIBUTION ==========")
print(all_distribution.to_string())


# =====================================================
# 12. EPC Rating Time Comparison
# =====================================================

rating_comparison = pd.DataFrame({
    "train_D_G_pct": train_distribution["D_G_percentage"],
    "test_D_G_pct": test_distribution["D_G_percentage"],
    "train_F_G_pct": train_distribution["F_G_percentage"],
    "test_F_G_pct": test_distribution["F_G_percentage"]
})

rating_comparison["D_G_change_pp"] = (
    rating_comparison["test_D_G_pct"]
    - rating_comparison["train_D_G_pct"]
)

rating_comparison["F_G_change_pp"] = (
    rating_comparison["test_F_G_pct"]
    - rating_comparison["train_F_G_pct"]
)

print("\n========== EPC RATING TIME COMPARISON ==========")
print(rating_comparison.round(2).to_string())


# =====================================================
# 13. Export EPC Rating Results
# =====================================================

train_distribution.to_csv(
    OUTPUT_DIR / "cluster_epc_rating_distribution_6features_train.csv",
    encoding="utf-8-sig"
)

test_distribution.to_csv(
    OUTPUT_DIR / "cluster_epc_rating_distribution_6features_test.csv",
    encoding="utf-8-sig"
)

all_distribution.to_csv(
    OUTPUT_DIR / "cluster_epc_rating_distribution_6features_all.csv",
    encoding="utf-8-sig"
)

rating_comparison.to_csv(
    OUTPUT_DIR / "cluster_epc_rating_time_comparison_6features.csv",
    encoding="utf-8-sig"
)

print("\nEPC rating distribution analysis completed.")
