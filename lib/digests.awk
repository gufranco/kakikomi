function label(text) {
  if (text ~ /sha3/) {
    if (text ~ /sha3[-_]?224/) return "sha3-224"
    if (text ~ /sha3[-_]?256/) return "sha3-256"
    if (text ~ /sha3[-_]?384/) return "sha3-384"
    if (text ~ /sha3[-_]?512/) return "sha3-512"
    return "unknown"
  }
  if (text ~ /blake2s|blake2b?[-_]?(160|224|256|384)/) return "unknown"
  if (text ~ /blake2|(^|[^a-z0-9])b2(sums?)?([^a-z0-9]|$)/) return "blake2b"
  if (text ~ /sha2?[-_]?512/) return "sha512"
  if (text ~ /sha2?[-_]?384/) return "sha384"
  if (text ~ /sha2?[-_]?256/) return "sha256"
  if (text ~ /sha2?[-_]?224/) return "sha224"
  if (text ~ /sha[-_]?1([^0-9]|$)/) return "sha1"
  if (text ~ /md[-_]?5/) return "md5"
  if (text ~ /crc[-_]?32|\.sfv$/) return "crc32"
  return ""
}

function bounded(text, at, size,   before, after) {
  before = at > 1 ? substr(text, at - 1, 1) : ""
  after = substr(text, at + size, 1)
  return (before == "" || index(" \t*(/\\\"':", before) > 0) && (after == "" || index(" \t)\"':,;", after) > 0)
}

function blank_names(text,   i, at, from, size, found) {
  found = 0
  for (i = 1; i <= count; i++) {
    size = length(names[i])
    if (size == 0) continue
    from = 1
    while ((at = index(substr(text, from), names[i])) > 0) {
      at += from - 1
      if (bounded(text, at, size)) {
        text = substr(text, 1, at - 1) sprintf("%" size "s", "") substr(text, at + size)
        found = 1
      }
      from = at + size
    }
  }
  rest = text
  return found
}

function collect(text, line_label,   words, n, i, size, kind) {
  if (text ~ /^[ \t]*[0-9a-f][0-9a-f]( [0-9a-f][0-9a-f])+[ \t]*$/) gsub(/ /, "", text)
  gsub(/[^0-9a-z]+/, " ", text)
  n = split(text, words, " ")
  found_count = 0
  for (i = 1; i <= n; i++) {
    if (words[i] !~ /^[0-9a-f]+$/) continue
    size = length(words[i])
    kind = line_label != "" ? line_label : (context != "" ? context : hint)
    if (kind == "unknown") continue
    if (kind == "" || width[kind] != size) {
      if (line_label != "") continue
      kind = size == 8 ? (crc_ok ? "crc32" : "") : by_width[size]
    }
    if (kind == "") continue
    found_count++
    found_hex[found_count] = words[i]
    found_kind[found_count] = kind
  }
  return found_count
}

function emit(kind, algorithm, hex) {
  if ((algorithm " " hex) in printed) return
  printed[algorithm " " hex] = 1
  print kind, algorithm, hex
  named_any = named_any || kind == "named"
}

function lone_line(text) {
  return found_count == 1 && text !~ /[.\/\\]/
}

BEGIN {
  REMARK = "^[ \t]*[#;]"
  split("md5 32 sha1 40 sha224 56 sha256 64 sha384 96 sha512 128 blake2b 128 crc32 8 sha3-224 56 sha3-256 64 sha3-384 96 sha3-512 128 sha512-or-blake2b 128", table, " ")
  for (i = 1; i in table; i += 2) width[table[i]] = table[i + 1] + 0
  by_width[32] = "md5"
  by_width[40] = "sha1"
  by_width[56] = "sha224"
  by_width[64] = "sha256"
  by_width[96] = "sha384"
  by_width[128] = "sha512-or-blake2b"
  count = split(tolower(ENVIRON["DISK_DIGEST_NAMES"]), names, "\n")
  tied = ENVIRON["DISK_DIGEST_TIED"] == "1"
  blank_names(tolower(ENVIRON["DISK_DIGEST_FILE"]))
  hint = label(rest)
  context = ""
}

{
  line = $0
  sub(/\r$/, "", line)
  if (line == "-----BEGIN PGP SIGNED MESSAGE-----") { armor = 1; next }
  if (armor) { if (line == "") armor = 0; next }
  if (line == "-----BEGIN PGP SIGNATURE-----") { signature = 1; next }
  if (signature) { if (line == "-----END PGP SIGNATURE-----") signature = 0; next }
  sub(/^- /, "", line)
  named = blank_names(tolower(line))
  line_label = label(rest)
  crc_ok = hint == "crc32" || line_label == "crc32" || context == "crc32"
  digits = collect(rest, line_label)
  if (rest ~ REMARK) {
    if (line_label != "" && digits == 0) context = line_label
    pending = 0
    last_lone = 0
    next
  }
  if (digits == 0) {
    if (line_label != "") context = line_label
    if (named && last_lone) emit("named", last_kind, last_hex)
    pending = named
    if (rest !~ /^[ \t]*$/) last_lone = 0
    next
  }
  if (named) {
    for (i = 1; i <= digits; i++) emit("named", found_kind[i], found_hex[i])
    pending = 0
    last_lone = 0
    next
  }
  lone = lone_line(rest)
  if (pending && lone) emit("named", found_kind[1], found_hex[1])
  pending = 0
  if (!lone) listed = 1
  last_lone = lone
  last_kind = found_kind[1]
  last_hex = found_hex[1]
  for (i = 1; i <= digits; i++) {
    if (!(found_hex[i] in bare)) bare_count++
    bare[found_hex[i]] = found_kind[i]
  }
}

END {
  if (named_any || bare_count != 1) exit
  for (hex in bare) {
    if (tied) emit("named", bare[hex], hex)
    else if (!listed) emit("loose", bare[hex], hex)
  }
}
