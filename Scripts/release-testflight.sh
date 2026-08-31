#!/bin/zsh

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPO_ROOT="${SCRIPT_DIR:h}"
readonly PROJECT_PATH="${REPO_ROOT}/Ilumionate.xcodeproj"
readonly PROJECT_FILE="${PROJECT_PATH}/project.pbxproj"
readonly SCHEME="Ilumionate"
readonly BUNDLE_ID="com.byronquine.lumenSync"
readonly SHARE_EXTENSION_BUNDLE_ID="com.byronquine.lumenSync.ShareExtension"
readonly EXPORT_OPTIONS="${REPO_ROOT}/ExportOptionsTestFlight.plist"

requested_version=""
requested_group="${TESTFLIGHT_GROUP:-}"
use_group=1
dry_run=0

usage() {
  /bin/echo "Usage: Scripts/release-testflight.sh [options]"
  /bin/echo
  /bin/echo "Build, upload, process, and internally distribute an Ilumionate TestFlight build."
  /bin/echo
  /bin/echo "Options:"
  /bin/echo "  --version X.Y.Z  Use an explicit marketing version (default: increment patch)"
  /bin/echo "  --group NAME      Add the build to this internal TestFlight group"
  /bin/echo "  --no-group        Upload and process without assigning a TestFlight group"
  /bin/echo "  --dry-run         Resolve and print the release plan without changing files"
  /bin/echo "  -h, --help        Show this help"
}

fail() {
  /bin/echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

read_project_versions() {
  /usr/bin/ruby -e '
    path, app_bundle, extension_bundle = ARGV
    text = File.read(path)
    blocks = text.scan(/buildSettings = \{.*?^\s+\};/m)

    # Read the app AND the extension together. Apple rejects an upload whose
    # extension version or build differs from its parent app (ITMS-90473), and
    # a release that only bumps the app produces exactly that. Checking both
    # here fails before any archive work rather than part-way through it.
    def blocks_for(blocks, bundle)
      blocks.select { |block| block.include?("PRODUCT_BUNDLE_IDENTIFIER = #{bundle};") }
    end

    app_blocks = blocks_for(blocks, app_bundle)
    extension_blocks = blocks_for(blocks, extension_bundle)
    abort "Expected two #{app_bundle} build configurations, found #{app_blocks.length}" unless app_blocks.length == 2
    abort "Expected two #{extension_bundle} build configurations, found #{extension_blocks.length}" unless extension_blocks.length == 2

    def field(blocks, key)
      blocks.map { |block| block[/#{key} = ([^;]+);/, 1] }.compact.uniq
    end

    app_versions = field(app_blocks, "MARKETING_VERSION")
    app_builds = field(app_blocks, "CURRENT_PROJECT_VERSION")
    ext_versions = field(extension_blocks, "MARKETING_VERSION")
    ext_builds = field(extension_blocks, "CURRENT_PROJECT_VERSION")

    abort "App marketing versions are missing or inconsistent: #{app_versions.inspect}" unless app_versions.length == 1
    abort "App build numbers are missing or inconsistent: #{app_builds.inspect}" unless app_builds.length == 1
    abort "Extension marketing versions are missing or inconsistent: #{ext_versions.inspect}" unless ext_versions.length == 1
    abort "Extension build numbers are missing or inconsistent: #{ext_builds.inspect}" unless ext_builds.length == 1

    unless app_versions.first == ext_versions.first && app_builds.first == ext_builds.first
      abort <<~MESSAGE
        Extension version does not match the app, which Apple rejects on upload.
          app       #{app_bundle}: #{app_versions.first} (#{app_builds.first})
          extension #{extension_bundle}: #{ext_versions.first} (#{ext_builds.first})
        Align them in #{path} before releasing.
      MESSAGE
    end

    puts "#{app_versions.first}|#{app_builds.first}"
  ' "${PROJECT_FILE}" "${BUNDLE_ID}" "${SHARE_EXTENSION_BUNDLE_ID}"
}

increment_patch_version() {
  /usr/bin/ruby -e '
    parts = ARGV.fetch(0).split(".")
    abort "Version must contain one to three numeric components" unless (1..3).cover?(parts.length)
    abort "Version must contain only numeric components" unless parts.all? { |part| part.match?(/\A\d+\z/) }
    parts << "0" while parts.length < 3
    parts[2] = (parts[2].to_i + 1).to_s
    puts parts.join(".")
  ' "$1"
}

set_project_versions() {
  local from_version="$1"
  local to_version="$2"
  local from_build="$3"
  local to_build="$4"

  /usr/bin/ruby -e '
    path, app_bundle, extension_bundle, from_version, to_version, from_build, to_build = ARGV
    text = File.read(path)
    changed = 0

    updated = text.gsub(/buildSettings = \{.*?^\s+\};/m) do |block|
      target = block.include?("PRODUCT_BUNDLE_IDENTIFIER = #{app_bundle};") ||
        block.include?("PRODUCT_BUNDLE_IDENTIFIER = #{extension_bundle};")
      next block unless target

      expected_version = "MARKETING_VERSION = #{from_version};"
      expected_build = "CURRENT_PROJECT_VERSION = #{from_build};"
      abort "Unexpected version in an Ilumionate release configuration" unless block.include?(expected_version)
      abort "Unexpected build number in an Ilumionate release configuration" unless block.include?(expected_build)

      changed += 1
      block.sub(expected_version, "MARKETING_VERSION = #{to_version};")
        .sub(expected_build, "CURRENT_PROJECT_VERSION = #{to_build};")
    end

    abort "Expected four app/extension configurations, changed #{changed}" unless changed == 4

    temporary = "#{path}.testflight-release-tmp"
    File.write(temporary, updated)
    File.rename(temporary, path)
  ' "${PROJECT_FILE}" "${BUNDLE_ID}" "${SHARE_EXTENSION_BUNDLE_ID}" \
    "${from_version}" "${to_version}" "${from_build}" "${to_build}"
}

json_app_id() {
  /usr/bin/ruby -rjson -e '
    bundle = ARGV.fetch(0)
    json = JSON.parse(STDIN.read)
    records = json.is_a?(Hash) ? Array(json["data"]) : []
    match = records.find do |record|
      attributes = record.is_a?(Hash) ? record["attributes"] : nil
      attributes.is_a?(Hash) && attributes["bundleId"] == bundle
    end
    abort "App Store Connect returned no app for bundle ID #{bundle}" unless match
    abort "App Store Connect app record has no ID" unless match["id"]
    puts match["id"]
  ' "${BUNDLE_ID}"
}

json_next_build_number() {
  /usr/bin/ruby -rjson -e '
    json = JSON.parse(STDIN.read)
    if json.is_a?(String) || json.is_a?(Numeric)
      puts json
      exit
    end

    found = nil
    walk = lambda do |value|
      case value
      when Hash
        value.each do |key, child|
          if key.to_s.gsub(/[^a-z]/i, "").downcase == "nextbuildnumber"
            found = child
            break
          end
          walk.call(child) unless found
        end
      when Array
        value.each { |child| walk.call(child) unless found }
      end
    end
    walk.call(json)
    abort "Could not read next build number from asc output" unless found.to_s.match?(/\A\d+\z/)
    puts found
  '
}

json_internal_group() {
  /usr/bin/ruby -rjson -e '
    requested = ARGV.first.to_s
    json = JSON.parse(STDIN.read)
    groups = json.is_a?(Hash) ? Array(json["data"]) : []
    selected = if requested.empty?
      preferred = groups.find do |group|
        name = group.dig("attributes", "name").to_s.downcase
        ["internal testing", "internal testers"].include?(name)
      end
      preferred || groups.first
    else
      groups.find do |group|
        group["id"] == requested || group.dig("attributes", "name") == requested
      end
    end
    exit 2 unless selected
    name = selected.dig("attributes", "name") || "internal group"
    all_builds = selected.dig("attributes", "hasAccessToAllBuilds") == true
    puts "#{selected.fetch("id")}|#{name}|#{all_builds}"
  ' "$1"
}

while (( $# > 0 )); do
  case "$1" in
    --version)
      (( $# >= 2 )) || fail "--version requires a value"
      requested_version="$2"
      shift 2
      ;;
    --group)
      (( $# >= 2 )) || fail "--group requires a value"
      requested_group="$2"
      shift 2
      ;;
    --no-group)
      use_group=0
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

require_command asc
require_command xcodebuild
require_command ruby

[[ -f "${PROJECT_FILE}" ]] || fail "Missing Xcode project: ${PROJECT_PATH}"
[[ -f "${EXPORT_OPTIONS}" ]] || fail "Missing export options: ${EXPORT_OPTIONS}"

project_versions="$(read_project_versions)"
current_version="${project_versions%%|*}"
current_build="${project_versions##*|}"
[[ "${current_build}" == <-> ]] || fail "Current build number is not numeric: ${current_build}"

if [[ -n "${requested_version}" ]]; then
  next_version="${requested_version}"
  increment_patch_version "${next_version}" >/dev/null
else
  next_version="$(increment_patch_version "${current_version}")"
fi

if ! apps_json="$(asc apps list --bundle-id "${BUNDLE_ID}" --output json)"; then
  /bin/echo >&2
  /bin/echo "App Store Connect authentication is not ready." >&2
  /bin/echo "Run asc auth login once with a team API key stored in the macOS keychain." >&2
  exit 1
fi
app_id="$(/bin/echo -n "${apps_json}" | json_app_id)"

initial_build="$(( current_build + 1 ))"
next_build_json="$(asc builds next-build-number \
  --app "${app_id}" \
  --version "${next_version}" \
  --platform IOS \
  --initial-build-number "${initial_build}" \
  --output json)"
next_build="$(/bin/echo -n "${next_build_json}" | json_next_build_number)"

group_id=""
group_name=""
group_has_access_to_all_builds="false"
if (( use_group )); then
  internal_groups_json="$(asc testflight groups list --app "${app_id}" --internal --paginate --output json)"
  if group_record="$(/bin/echo -n "${internal_groups_json}" | json_internal_group "${requested_group}")"; then
    group_id="${group_record%%|*}"
    group_details="${group_record#*|}"
    group_name="${group_details%%|*}"
    group_has_access_to_all_builds="${group_details##*|}"
  elif [[ -n "${requested_group}" ]]; then
    fail "No internal TestFlight group matched: ${requested_group}"
  else
    /bin/echo "warning: no internal TestFlight group found; the build will be uploaded without group assignment" >&2
  fi
fi

/bin/echo "Ilumionate TestFlight release"
/bin/echo "  App Store Connect app: ${app_id}"
/bin/echo "  Version: ${current_version} -> ${next_version}"
/bin/echo "  Build: ${current_build} -> ${next_build}"
if [[ -n "${group_name}" ]]; then
  if [[ "${group_has_access_to_all_builds}" == "true" ]]; then
    /bin/echo "  Internal group: ${group_name} (automatic access to all builds)"
  else
    /bin/echo "  Internal group: ${group_name}"
  fi
else
  /bin/echo "  Internal group: none"
fi

if (( dry_run )); then
  /bin/echo "Dry run complete; no files were changed and no build was uploaded."
  exit 0
fi

release_directory="$(mktemp -d "/tmp/Ilumionate-TestFlight-${next_version}-${next_build}.XXXXXX")"
archive_path="${release_directory}/Ilumionate.xcarchive"
export_path="${release_directory}/Export"
versions_changed=0
upload_committed=0

rollback_if_needed() {
  local exit_code=$?
  if (( exit_code != 0 && versions_changed && ! upload_committed )); then
    /bin/echo "Release failed before upload; restoring project version values." >&2
    set_project_versions "${next_version}" "${current_version}" "${next_build}" "${current_build}" || true
  fi
  if (( exit_code != 0 )); then
    /bin/echo "Release artifacts remain at: ${release_directory}" >&2
  fi
  exit "${exit_code}"
}
trap rollback_if_needed EXIT

set_project_versions "${current_version}" "${next_version}" "${current_build}" "${next_build}"
versions_changed=1

xcodebuild clean archive \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "${archive_path}" \
  -allowProvisioningUpdates

xcodebuild -exportArchive \
  -archivePath "${archive_path}" \
  -exportPath "${export_path}" \
  -exportOptionsPlist "${EXPORT_OPTIONS}" \
  -allowProvisioningUpdates

ipa_path="$(find "${export_path}" -maxdepth 1 -type f -name '*.ipa' -print -quit)"
[[ -n "${ipa_path}" ]] || fail "Xcode export completed without producing an IPA"

asc builds upload \
  --app "${app_id}" \
  --ipa "${ipa_path}" \
  --version "${next_version}" \
  --build-number "${next_build}" \
  --output json
upload_committed=1

asc builds wait \
  --app "${app_id}" \
  --build-number "${next_build}" \
  --version "${next_version}" \
  --platform IOS \
  --timeout 30m \
  --poll-interval 30s \
  --fail-on-invalid \
  --output table

if [[ "${group_has_access_to_all_builds}" == "true" ]]; then
  /bin/echo "Internal group ${group_name} already receives every valid build automatically."
elif [[ -n "${group_id}" ]]; then
  asc builds add-groups \
    --app "${app_id}" \
    --build-number "${next_build}" \
    --version "${next_version}" \
    --platform IOS \
    --group "${group_id}" \
    --output table
fi

trap - EXIT
/bin/echo
/bin/echo "TestFlight upload complete: Ilumionate ${next_version} (${next_build})"
/bin/echo "Release artifacts: ${release_directory}"
