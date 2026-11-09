#!/usr/bin/env python3
"""
RiskDM formal experiment — merge xlsx files and visualize language priming effects.

Usage:
    python visualize_riskdm.py
    python visualize_riskdm.py --data-dir /path/to/folder/with/xlsx

Requires: pandas, matplotlib, seaborn, openpyxl
    pip install pandas matplotlib seaborn openpyxl
"""

from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns

# ---------------------------------------------------------------------------
# Style
# ---------------------------------------------------------------------------
sns.set_theme(style="whitegrid", context="talk", font_scale=0.9)
CONDITION_ORDER = ["adventure", "neutral", "conservative"]
CONDITION_LABELS = {
    "adventure": "鼓励冒险",
    "neutral": "中性",
    "conservative": "鼓励保守",
}
CONDITION_COLORS = {
    "adventure": "#E74C3C",
    "neutral": "#95A5A6",
    "conservative": "#3498DB",
}


def setup_chinese_font() -> None:
    """Use a CJK font on macOS/Windows so Chinese titles render."""
    import sys

    from matplotlib import font_manager

    candidates = [
        "PingFang SC",
        "Heiti SC",
        "STHeiti",
        "Microsoft YaHei",
        "SimHei",
        "Arial Unicode MS",
    ]
    available = {f.name for f in font_manager.fontManager.ttflist}
    for name in candidates:
        if name in available:
            plt.rcParams["font.sans-serif"] = [name, "DejaVu Sans"]
            plt.rcParams["axes.unicode_minus"] = False
            return
    if sys.platform == "darwin":
        plt.rcParams["font.sans-serif"] = ["PingFang SC", "DejaVu Sans"]


def find_data_dir(cli_path: str | None) -> Path:
    script_dir = Path(__file__).resolve().parent
    if cli_path:
        p = Path(cli_path).expanduser().resolve()
        if not p.is_dir():
            raise SystemExit(f"Data directory not found: {p}")
        return p
    if list(script_dir.glob("RiskDM_FormalData_*.xlsx")):
        return script_dir
    raise SystemExit(
        "No RiskDM_FormalData_*.xlsx found. Use --data-dir to point at your folder."
    )


def load_all_xlsx(data_dir: Path) -> pd.DataFrame:
    files = sorted(data_dir.glob("RiskDM_FormalData_*.xlsx"))
    if not files:
        raise SystemExit(f"No xlsx files in {data_dir}")
    parts = []
    for f in files:
        # Unique ID from filename (avoids duplicate SubID in xlsx, e.g. 008 vs 009)
        stem = f.stem.replace("RiskDM_FormalData_", "")
        file_sub = stem.split("_", 1)[0]
        chunk = pd.read_excel(f)
        chunk["SubID_file"] = file_sub
        chunk["SubID_raw"] = chunk["SubID"].astype(str).str.strip()
        chunk["SubID"] = file_sub
        parts.append(chunk)
    df = pd.concat(parts, ignore_index=True)
    dup_raw = df.groupby("SubID_raw")["SubID_file"].nunique()
    bad = dup_raw[dup_raw > 1]
    if len(bad):
        print("NOTE: same SubID_raw in multiple files — using SubID from filename:")
        for k in bad.index:
            files_ids = df.loc[df["SubID_raw"] == k, "SubID_file"].unique()
            print(f"  raw SubID {k!r} -> files {list(files_ids)}")
    return df


def prepare_trial_df(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    numeric_cols = [
        "Baseline_Alpha",
        "Block",
        "Trial",
        "Probability",
        "ST_Amount",
        "RG_Amount",
        "Choice_Num",
        "RT_sec",
        "Reward",
        "Trial_Indif_Alpha",
    ]
    for c in numeric_cols:
        if c in df.columns:
            df[c] = pd.to_numeric(df[c], errors="coerce")

    df["Block"] = df["Block"].astype(int)
    df["Trial"] = df["Trial"].astype(int)
    df["Condition"] = pd.Categorical(
        df["Condition"].str.lower().str.strip(),
        categories=CONDITION_ORDER,
        ordered=True,
    )
    df["chose_RG"] = (df["Choice_Label"] == "RG").astype(float)
    df["valid_choice"] = df["Choice_Label"].isin(["ST", "RG"])
    return df


def build_block_summary(df: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for (sub, block), g in df.groupby(["SubID", "Block"], sort=True):
        g = g.sort_values("Trial")
        valid = g[g["valid_choice"]]
        rows.append(
            {
                "SubID": sub,
                "Block": block,
                "Condition": g["Condition"].iloc[0],
                "Initial_Alpha": g["Trial_Indif_Alpha"].iloc[0],
                "Final_Alpha": g["Trial_Indif_Alpha"].iloc[-1],
                "Delta_Alpha": g["Trial_Indif_Alpha"].iloc[-1]
                - g["Trial_Indif_Alpha"].iloc[0],
                "RG_rate": valid["chose_RG"].mean() if len(valid) else np.nan,
                "mean_RT": valid["RT_sec"].mean() if len(valid) else np.nan,
                "n_timeout": (g["Choice_Label"] == "Timeout").sum(),
            }
        )
    return pd.DataFrame(rows)


def subject_condition_means(block_df: pd.DataFrame) -> pd.DataFrame:
    agg = (
        block_df.groupby(["SubID", "Condition"], observed=True)
        .agg(
            Final_Alpha=("Final_Alpha", "mean"),
            RG_rate=("RG_rate", "mean"),
            mean_RT=("mean_RT", "mean"),
        )
        .reset_index()
    )
    return agg


def print_qc(df: pd.DataFrame, block_df: pd.DataFrame) -> None:
    print("=" * 60)
    print("DATA QC")
    print("=" * 60)
    print(f"Trials: {len(df):,}  |  Subjects: {df['SubID'].nunique()}")
    print("Files pattern: RiskDM_FormalData_*.xlsx")
    trials_per_sub = df.groupby("SubID").size()
    print(f"Trials/subject: min={trials_per_sub.min()}, max={trials_per_sub.max()}")

    block_cond = block_df.groupby("Block")["Condition"].nunique()
    if (block_cond > 1).any():
        print("WARNING: some blocks have >1 condition")
    else:
        print("OK: each block has a single condition")

    print("\nTrials per condition:")
    print(df["Condition"].value_counts().sort_index().to_string())
    n_to = (df["Choice_Label"] == "Timeout").sum()
    print(f"\nTimeouts: {n_to} ({100 * n_to / len(df):.2f}%)")
    print("=" * 60)


def save_fig(path: Path) -> None:
    plt.tight_layout()
    plt.savefig(path, dpi=150, bbox_inches="tight")
    plt.close()
    print(f"  saved: {path.name}")


def plot_rg_bar(sub_cond: pd.DataFrame, out_dir: Path) -> None:
    fig, ax = plt.subplots(figsize=(7, 5))
    order = CONDITION_ORDER
    sns.barplot(
        data=sub_cond,
        x="Condition",
        y="RG_rate",
        order=order,
        hue="Condition",
        palette=[CONDITION_COLORS[c] for c in order],
        errorbar=("ci", 95),
        capsize=0.08,
        legend=False,
        ax=ax,
    )
    ax.set_xticklabels([CONDITION_LABELS[c] for c in order])
    ax.set_ylabel("RG 选择比例")
    ax.set_xlabel("")
    ax.set_ylim(0, 1)
    ax.set_title("三种语言条件下的风险选择比例\n（被试内条件均值，误差线 95% CI）")
    save_fig(out_dir / "01_RG_rate_by_condition.png")


def plot_rg_paired(sub_cond: pd.DataFrame, out_dir: Path) -> None:
    fig, ax = plt.subplots(figsize=(8, 5))
    wide = sub_cond.pivot(index="SubID", columns="Condition", values="RG_rate")
    x_pos = np.arange(len(CONDITION_ORDER))
    for sub in wide.index:
        ys = [wide.loc[sub, c] if c in wide.columns else np.nan for c in CONDITION_ORDER]
        ax.plot(x_pos, ys, "o-", color="#BDC3C7", alpha=0.7, markersize=5, linewidth=1)
    means = [wide[c].mean() for c in CONDITION_ORDER]
    ax.plot(x_pos, means, "D-", color="#2C3E50", markersize=10, linewidth=2.5, label="组均值")
    ax.set_xticks(x_pos)
    ax.set_xticklabels([CONDITION_LABELS[c] for c in CONDITION_ORDER])
    ax.set_ylabel("RG 选择比例")
    ax.set_ylim(0, 1)
    ax.set_title("被试内配对：各条件下的 RG 比例")
    ax.legend(loc="upper right")
    save_fig(out_dir / "02_RG_rate_paired.png")


def plot_alpha_violin(sub_cond: pd.DataFrame, out_dir: Path) -> None:
    fig, ax = plt.subplots(figsize=(7, 5))
    sns.violinplot(
        data=sub_cond,
        x="Condition",
        y="Final_Alpha",
        order=CONDITION_ORDER,
        hue="Condition",
        palette=[CONDITION_COLORS[c] for c in CONDITION_ORDER],
        inner="box",
        cut=0,
        legend=False,
        ax=ax,
    )
    sns.stripplot(
        data=sub_cond,
        x="Condition",
        y="Final_Alpha",
        order=CONDITION_ORDER,
        color="#2C3E50",
        alpha=0.45,
        size=4,
        jitter=0.12,
        ax=ax,
    )
    ax.set_xticklabels([CONDITION_LABELS[c] for c in CONDITION_ORDER])
    ax.set_ylabel("Block 末 Alpha（PSE，越大越保守）")
    ax.set_xlabel("")
    ax.set_title("主观风险中性点：三种条件下的 Final Alpha\n（每条件 3 个 block 的被试内均值）")
    save_fig(out_dir / "03_Final_Alpha_by_condition.png")


def plot_rt(sub_cond: pd.DataFrame, out_dir: Path) -> None:
    fig, ax = plt.subplots(figsize=(7, 5))
    sns.boxplot(
        data=sub_cond,
        x="Condition",
        y="mean_RT",
        order=CONDITION_ORDER,
        hue="Condition",
        palette=[CONDITION_COLORS[c] for c in CONDITION_ORDER],
        width=0.55,
        legend=False,
        ax=ax,
    )
    ax.set_xticklabels([CONDITION_LABELS[c] for c in CONDITION_ORDER])
    ax.set_ylabel("反应时 (秒)")
    ax.set_xlabel("")
    ax.set_title("平均反应时（按条件，被试内 block 均值）")
    save_fig(out_dir / "04_RT_by_condition.png")


def plot_alpha_trajectory(df: pd.DataFrame, out_dir: Path) -> None:
    """Mean Trial_Indif_Alpha across trials 1-24, per condition (block-internal trial number)."""
    valid = df[df["valid_choice"]].copy()
    traj = (
        valid.groupby(["Condition", "Trial"], observed=True)["Trial_Indif_Alpha"]
        .agg(["mean", "sem"])
        .reset_index()
    )
    fig, ax = plt.subplots(figsize=(9, 5))
    for cond in CONDITION_ORDER:
        sub = traj[traj["Condition"] == cond]
        ax.plot(
            sub["Trial"],
            sub["mean"],
            label=CONDITION_LABELS[cond],
            color=CONDITION_COLORS[cond],
            linewidth=2,
        )
        ax.fill_between(
            sub["Trial"],
            sub["mean"] - sub["sem"],
            sub["mean"] + sub["sem"],
            color=CONDITION_COLORS[cond],
            alpha=0.2,
        )
    ax.set_xlabel("Block 内试次编号")
    ax.set_ylabel("Trial_Indif_Alpha")
    ax.set_title("Block 内 Alpha 轨迹（跨被试均值 ± SEM）")
    ax.legend()
    save_fig(out_dir / "05_alpha_trajectory_by_trial.png")


def plot_rg_by_block_index(block_df: pd.DataFrame, out_dir: Path) -> None:
    """RG rate vs block number 1-9 (checks order/fatigue; not pure condition)."""
    by_block = block_df.groupby("Block")["RG_rate"].agg(["mean", "sem"]).reset_index()
    fig, ax = plt.subplots(figsize=(8, 4))
    ax.errorbar(
        by_block["Block"],
        by_block["mean"],
        yerr=by_block["sem"],
        fmt="o-",
        capsize=4,
        color="#34495E",
    )
    ax.set_xlabel("Block 编号（含 counterbalance 顺序）")
    ax.set_ylabel("RG 比例（block 均值）")
    ax.set_title("RG 比例随 Block 序号变化（探索性）")
    ax.set_xticks(range(1, 10))
    save_fig(out_dir / "06_RG_rate_by_block_number.png")


def paired_tests(sub_cond: pd.DataFrame) -> pd.DataFrame:
    from scipy import stats

    rows = []
    pairs = [
        ("adventure", "conservative"),
        ("adventure", "neutral"),
        ("conservative", "neutral"),
    ]
    for dv, label in [("RG_rate", "RG%"), ("Final_Alpha", "Final_Alpha")]:
        wide = sub_cond.pivot(index="SubID", columns="Condition", values=dv)
        for a, b in pairs:
            if a not in wide.columns or b not in wide.columns:
                continue
            mask = wide[[a, b]].notna().all(axis=1)
            x, y = wide.loc[mask, a], wide.loc[mask, b]
            if len(x) < 3:
                continue
            t, p = stats.ttest_rel(x, y)
            d = (x.mean() - y.mean()) / x.sub(y).std(ddof=1) if x.sub(y).std(ddof=1) > 0 else np.nan
            rows.append(
                {
                    "DV": label,
                    "A": a,
                    "B": b,
                    "mean_A": x.mean(),
                    "mean_B": y.mean(),
                    "diff_A_minus_B": x.mean() - y.mean(),
                    "t": t,
                    "p": p,
                    "cohen_dz": d,
                    "n": len(x),
                }
            )
    return pd.DataFrame(rows)


def main() -> None:
    setup_chinese_font()
    parser = argparse.ArgumentParser(description="Visualize RiskDM formal data")
    parser.add_argument(
        "--data-dir",
        type=str,
        default=None,
        help="Folder containing RiskDM_FormalData_*.xlsx (default: script folder)",
    )
    parser.add_argument(
        "--out-dir",
        type=str,
        default=None,
        help="Output folder for figures (default: data-dir/figures)",
    )
    args = parser.parse_args()

    data_dir = find_data_dir(args.data_dir)
    out_dir = Path(args.out_dir).expanduser().resolve() if args.out_dir else data_dir / "figures"
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"Data: {data_dir}")
    print(f"Output: {out_dir}\n")

    df = load_all_xlsx(data_dir)
    df = prepare_trial_df(df)
    block_df = build_block_summary(df)
    sub_cond = subject_condition_means(block_df)

    print_qc(df, block_df)

    # Save tables
    merged_path = data_dir / "RiskDM_FormalData_merged.csv"
    df.to_csv(merged_path, index=False, encoding="utf-8-sig")
    block_df.to_csv(data_dir / "RiskDM_FormalData_block_summary.csv", index=False, encoding="utf-8-sig")
    sub_cond.to_csv(data_dir / "RiskDM_subject_by_condition.csv", index=False, encoding="utf-8-sig")
    print(f"\nWrote: {merged_path.name}, block_summary, subject_by_condition")

    stats_df = paired_tests(sub_cond)
    stats_path = out_dir / "paired_ttests.csv"
    stats_df.to_csv(stats_path, index=False, encoding="utf-8-sig")
    print(f"\nPaired t-tests:\n{stats_df.to_string(index=False)}")
    print(f"Saved: {stats_path}")

    print("\nGenerating figures...")
    plot_rg_bar(sub_cond, out_dir)
    plot_rg_paired(sub_cond, out_dir)
    plot_alpha_violin(sub_cond, out_dir)
    plot_rt(sub_cond, out_dir)
    plot_alpha_trajectory(df, out_dir)
    plot_rg_by_block_index(block_df, out_dir)

    print(f"\nDone. Open folder: {out_dir}")


if __name__ == "__main__":
    main()
