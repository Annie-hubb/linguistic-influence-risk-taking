# RiskDM trial-level logistic mixed models
# Tests whether the linguistic prime condition shifts risky-gamble choice,
# with and without by-participant random condition slopes.
#
# Input: merged formal-task data (one row per trial), e.g. merged_raw_data30.csv,
#   with columns SubID, Condition (adventure / neutral / conservative),
#   Choice_Num (1 = risky gamble, 0 = sure thing, 2 = timeout), Probability.
# Usage: Rscript riskdm_glmm.R [path/to/merged_raw_data30.csv]
# Requires: lme4

suppressMessages(library(lme4))

args <- commandArgs(trailingOnly = TRUE)
data_path <- if (length(args) >= 1) args[1] else "merged_raw_data30.csv"

d <- read.csv(data_path)
d <- subset(d, Choice_Num %in% c(0, 1))          # drop timeouts
d$Condition <- relevel(factor(d$Condition), ref = "conservative")
d$SubID <- factor(d$SubID)
cat("Trials:", nrow(d), " Participants:", nlevels(d$SubID), "\n\n")

ctl <- glmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 2e5))

report <- function(m, label) {
  s <- coef(summary(m))
  r <- s[grep("Condition", rownames(s)), , drop = FALSE]
  out <- data.frame(
    model = label,
    term  = rownames(r),
    OR    = exp(r[, 1]),
    CI_lo = exp(r[, 1] - 1.96 * r[, 2]),
    CI_hi = exp(r[, 1] + 1.96 * r[, 2]),
    z     = r[, 3],
    p     = r[, 4],
    singular = isSingular(m),
    row.names = NULL
  )
  print(out, digits = 4); cat("\n")
  out
}

# 1. Random intercept only
m1 <- glmer(Choice_Num ~ Condition + (1 | SubID),
            data = d, family = binomial, control = ctl)
# 2. Random intercept + random condition slopes (preferred)
m2 <- glmer(Choice_Num ~ Condition + (1 + Condition | SubID),
            data = d, family = binomial, control = ctl)
# 3. Same as 2, neutral as reference (adventure vs neutral, conservative vs neutral)
d$Condition_nref <- relevel(d$Condition, ref = "neutral")
m3 <- glmer(Choice_Num ~ Condition_nref + (1 + Condition_nref | SubID),
            data = d, family = binomial, control = ctl)
# 4. Same as 2, adjusting for win probability
m4 <- glmer(Choice_Num ~ Condition + scale(Probability) + (1 + Condition | SubID),
            data = d, family = binomial, control = ctl)

res <- rbind(
  report(m1, "random intercept only"),
  report(m2, "random intercept + condition slopes"),
  report(m3, "condition slopes, neutral reference"),
  report(m4, "condition slopes + probability covariate")
)

cat("Likelihood-ratio test, intercept-only vs random-slopes model:\n")
print(anova(m1, m2))

write.csv(res, "riskdm_glmm_results.csv", row.names = FALSE)
cat("\nSaved riskdm_glmm_results.csv\n")
