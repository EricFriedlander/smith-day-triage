# Helper script to fix Shinylive deployment by manually adding compatible packages
# This script is run by GitHub Actions after shinylive::export()

# Define the packages to fetch manually
packages_to_fetch <- list(
  list(name = "shiny", version = "1.9.1.8002",
       url = "http://repo.r-wasm.org/bin/emscripten/contrib/4.4/shiny_1.9.1.8002.tgz"),
  list(name = "bslib", version = "0.9.0",
       url = "http://repo.r-wasm.org/bin/emscripten/contrib/4.4/bslib_0.9.0.tgz"),
  # NOTE: Do NOT add glue - it conflicts with the base Shinylive distribution (1.7.0 vs 1.8.0)
  list(name = "munsell", version = "0.5.1",
       url = "http://repo.r-wasm.org/bin/emscripten/contrib/4.4/munsell_0.5.1.tgz"),
  list(name = "colorspace", version = "2.1-1",
       url = "http://repo.r-wasm.org/bin/emscripten/contrib/4.4/colorspace_2.1-1.tgz")
)

# Base path for packages in the exported site
package_path_base <- "site/shinylive/webr/packages"
if (!dir.exists(package_path_base)) {
  stop("site directory does not exist or is not a valid shinylive export")
}

# Load metadata
metadata_path <- file.path(package_path_base, "metadata.rds")
meta <- readRDS(metadata_path)

# Download packages and update metadata
for (pkg in packages_to_fetch) {
  message(sprintf("Processing %s version %s...", pkg$name, pkg$version))
  
  # create directory (remove old if exists to avoid conflicts)
  pkg_dir <- file.path(package_path_base, pkg$name)
  if (dir.exists(pkg_dir)) unlink(pkg_dir, recursive = TRUE)
  if (!dir.exists(pkg_dir)) dir.create(pkg_dir, recursive = TRUE)
  
  # download file
  filename <- basename(pkg$url)
  destfile <- file.path(pkg_dir, filename)
  download.file(pkg$url, destfile, quiet = TRUE)
  
  # Create metadata entry
  entry <- list(
    name = pkg$name,
    version = pkg$version,
    ref = sprintf("%s@%s", pkg$name, pkg$version),
    cached = TRUE,
    assets = list(list(filename = filename, url = pkg$url)),
    type = "package",
    path = file.path("packages", pkg$name, filename)
  )
  
  # Update metadata
  meta[[pkg$name]] <- entry
}

# Remove conflicting glue package if it exists (the one bundled by default might be different)
# Wait, actually we WANT our manual glue entry to overwrite.
# But if there's a folder with a different version, it might be confusing.
# We'll rely on the metadata update to point to the new version.

saveRDS(meta, metadata_path)
message("Successfully patched Shinylive export.")
