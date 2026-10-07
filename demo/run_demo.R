# SCORCH demonstration: the example data, one configuration file, one command.
#
# Run from the top folder of the repository, after installing the package:
#     Rscript demo/run_demo.R
# The results appear in scorch_demo_output/.

library(scoRch.generator)

result <- run_scorch("demo/scorch_config.yaml")

cat("\nFiles written:\n")
cat(paste0("  scorch_demo_output/", list.files("scorch_demo_output", recursive = TRUE)), sep = "\n")
