# GBM_IpsiContra_ForestPlots.R
# Generates Ipsilateral and Contralateral Firth's Cox forest plots
# for MD, AD, and RD (FA already done separatel
library(readxl)
library(coxphf)
library(survival)   # ensure Surv() is loaded
library(ggplot2)
library(dplyr)
setwd("/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Figures/Cox_Hazard")

# ── Settings ──────────────────────────────────────────────────────────────────
DATA_FILE <- "/Users/rosenble/Desktop/GBM/Glioblastoma/Data/Tract_Overall_Stats_V2/GBM_DTI_Master_Compiled.xlsx"
METRICS   <- c("MD", "AD", "RD")
P_THRESH  <- 0.05

# ── Load survival data ────────────────────────────────────────────────────────
master <- read_excel(DATA_FILE, sheet = "Master")
colnames(master) <- c("Patient_ID", "Tumor_Side", "Survival", "Status",
                       "Tracts_Detected", "FA_Comp", "MD_Comp", "AD_Comp", "RD_Comp")

master <- master %>%
  filter(!is.na(Survival), Survival != "?", !is.na(Status), Status != "?") %>%
  mutate(Survival = as.numeric(Survival),
         Status   = as.numeric(Status)) %>%
  filter(!is.na(Survival), !is.na(Status))

cat("Master rows after filtering:", nrow(master), "\n")
cat("Events (Status=1):", sum(master$Status == 1, na.rm = TRUE), "\n")
cat("Unique Tumor_Side values:", paste(unique(master$Tumor_Side), collapse = ", "), "\n\n")

# ── Helper: run Firth's Cox per tract, return results df ─────────────────────
run_cox_per_tract <- function(metric_sheet, master, hemisphere) {

  df_metric <- read_excel(DATA_FILE, sheet = metric_sheet)
  colnames(df_metric)[1:2] <- c("Patient_ID", "Tumor_Side")

  # Tract base names with both Left and Right columns
  all_cols    <- colnames(df_metric)
  left_cols   <- all_cols[grepl(" Left$", all_cols)]
  tract_names <- gsub(" Left$", "", left_cols)
  tract_names <- tract_names[paste0(tract_names, " Right") %in% all_cols]

  cat("  Tracts found:", length(tract_names), "\n")

  # Merge with survival — drop df_metric's Tumor_Side to avoid conflict
  df_for_join <- df_metric %>%
    select(-Tumor_Side) %>%
    select(Patient_ID, everything())

  merged <- inner_join(
    master %>% select(Patient_ID, Tumor_Side, Survival, Status),
    df_for_join,
    by = "Patient_ID"
  ) %>%
    filter(!is.na(Survival), !is.na(Status))

  cat("  Rows after join:", nrow(merged), "\n")

  if (nrow(merged) == 0) {
    cat("  WARNING: inner_join returned 0 rows — check Patient_ID formats\n")
    return(data.frame(Tract = character(), logHR = numeric(), p = numeric(),
                      stringsAsFactors = FALSE))
  }

  results <- data.frame(
    Tract  = character(),
    logHR  = numeric(),
    p      = numeric(),
    stringsAsFactors = FALSE
  )

  for (tract in tract_names) {
    left_col  <- paste0(tract, " Left")
    right_col <- paste0(tract, " Right")

    # Assign ipsi/contra value based on tumor side
    vals <- mapply(function(side, lv, rv) {
      if (is.na(side) || is.na(lv) || is.na(rv)) return(NA_real_)
      if (hemisphere == "ipsilateral") {
        if (toupper(trimws(side)) == "R") rv else lv
      } else {
        if (toupper(trimws(side)) == "R") lv else rv
      }
    },
    merged$Tumor_Side,
    as.numeric(merged[[left_col]]),
    as.numeric(merged[[right_col]]),
    SIMPLIFY = TRUE)

    vals <- as.numeric(vals)

    complete_idx <- !is.na(vals) & !is.na(merged$Survival) & !is.na(merged$Status)
    if (sum(complete_idx) < 5) next

    surv_sub <- merged$Survival[complete_idx]
    stat_sub <- merged$Status[complete_idx]
    val_sub  <- vals[complete_idx]

    # Z-score scale: log(HR) = effect per SD change (stable across DTI units)
    val_scaled <- as.numeric(scale(val_sub))

    cox_data <- data.frame(time = surv_sub, status = stat_sub, predictor = val_scaled)
    fit <- tryCatch(
      coxphf(Surv(time, status) ~ predictor, data = cox_data),
      error   = function(e) { cat("  ERROR for tract", tract, ":", conditionMessage(e), "\n"); NULL },
      warning = function(w) {
        suppressWarnings(
          tryCatch(coxphf(Surv(time, status) ~ predictor, data = cox_data),
                   error = function(e2) NULL)
        )
      }
    )
    if (is.null(fit)) next

    logHR <- coef(fit)[1]
    p_val <- fit$prob[1]

    if (!is.finite(logHR) || abs(logHR) > 10) next   # exclude truly exploded estimates

    results <- rbind(results, data.frame(
      Tract = tract,
      logHR = logHR,
      p     = p_val,
      stringsAsFactors = FALSE
    ))
  }

  results
}

# ── Helper: make forest plot ──────────────────────────────────────────────────
make_forest_plot <- function(results, title_str) {
  results <- results %>%
    arrange(logHR) %>%
    mutate(
      Tract = factor(Tract, levels = Tract),
      Sig   = ifelse(p < P_THRESH, "p < 0.05 (uncorrected)", "p ≥ 0.05")
    )

  ggplot(results, aes(x = logHR, y = Tract, color = Sig)) +
    geom_point(size = 2.5) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "gray50") +
    scale_color_manual(
      values = c("p ≥ 0.05" = "black", "p < 0.05 (uncorrected)" = "red"),
      name   = NULL
    ) +
    labs(
      title = title_str,
      x     = "log(Hazard Ratio)",
      y     = "Tract"
    ) +
    theme_classic(base_size = 11) +
    theme(
      legend.position = c(0.85, 0.15),
      legend.text     = element_text(size = 9),
      plot.title      = element_text(size = 12, face = "bold"),
      axis.text.y     = element_text(size = 7.5)
    )
}

# ── Run for each metric and hemisphere ────────────────────────────────────────
pdf_files <- c()

for (metric in METRICS) {
  cat("\n=== Processing", metric, "===\n")

  for (hemi in c("ipsilateral", "contralateral")) {
    cat("\n  --", hemi, "--\n")

    results <- run_cox_per_tract(metric, master, hemi)

    if (nrow(results) == 0) {
      cat("  No results for", metric, hemi, "\n")
      next
    }

    n_sig <- sum(results$p < P_THRESH, na.rm = TRUE)
    cat("  Tracts modeled:", nrow(results), "| Significant (uncorrected):", n_sig, "\n")
    if (n_sig > 0) {
      cat("  Significant:", paste(results$Tract[results$p < P_THRESH], collapse = ", "), "\n")
    }

    title_str <- sprintf("%s Cox –– %s", tools::toTitleCase(hemi), metric)
    p <- make_forest_plot(results, title_str)

    fname <- sprintf("ForestPlot_%s_%s.pdf", hemi, metric)
    ggsave(fname, plot = p, width = 6, height = 8, units = "in")
    pdf_files <- c(pdf_files, fname)
    cat("  Saved:", fname, "\n")
  }
}

# ── Combine into summary PDFs ─────────────────────────────────────────────────
library(pdftools)

ipsi_files   <- pdf_files[grepl("ipsilateral",    pdf_files)]
contra_files <- pdf_files[grepl("contralateral",  pdf_files)]

if (length(ipsi_files) > 0) {
  pdf_combine(ipsi_files,  "GBM_ForestPlots_Ipsilateral_MD_AD_RD.pdf")
  cat("\nCombined ipsilateral PDF: GBM_ForestPlots_Ipsilateral_MD_AD_RD.pdf\n")
}
if (length(contra_files) > 0) {
  pdf_combine(contra_files, "GBM_ForestPlots_Contralateral_MD_AD_RD.pdf")
  cat("Combined contralateral PDF: GBM_ForestPlots_Contralateral_MD_AD_RD.pdf\n")
}

cat("\nDone.\n")
