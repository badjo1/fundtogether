# Text people type that other people read on money screens. Bidi overrides can make a title read as something it
# does not say, and invisible characters make two names look identical (docs/SECURITY_REVIEW.md, M6). NUL and other
# controls are removed for the same reason, and because PostgreSQL refuses NUL (L5).
module SafeText
  CONTROLS = /[\p{Cc}­͏؜ᅟᅠ឴឵᠋-᠎​-‏‪-‮⁠-⁯︀-️﻿￹-￻]/

  module_function

  def clean(value)
    return value unless value.is_a?(String)

    value.scrub("").gsub(CONTROLS, "").strip
  end

  # For telling people apart: case, spacing and compatibility forms do not make two names different.
  def comparable(value)
    clean(value.to_s).unicode_normalize(:nfkc).downcase.gsub(/\s+/, " ")
  end
end
