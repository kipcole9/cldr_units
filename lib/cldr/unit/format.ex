defmodule Cldr.Unit.Format do
  alias Cldr.Unit

  defmacrop is_grammar(unit) do
    quote do
      is_tuple(unquote(unit))
    end
  end

  @typep grammar ::
           {Unit.translatable_unit(),
            {Unit.grammatical_case(), Cldr.Number.PluralRule.plural_type()}}

  @typep grammar_list :: [grammar, ...]

  @translatable_units Cldr.Unit.known_units()
  @si_keys Cldr.Unit.Prefix.si_keys()
  @power_keys Cldr.Unit.Prefix.power_keys()

  @default_case :nominative
  @default_style :long
  @default_plural :other

  @doc """
  Formats a number into a string according to a unit definition
  for the current process's locale and backend.

  The curent process's locale is set with
  `Cldr.put_locale/1`.

  See `Cldr.Unit.to_string/3` for full details.

  """
  @spec to_string(list_or_number :: Unit.value() | Unit.t() | [Unit.t()]) ::
          {:ok, String.t()} | {:error, {atom, binary}}

  def to_string(unit) do
    locale = Cldr.get_locale()
    backend = locale.backend
    to_string(unit, backend, locale: locale)
  end

  @doc """
  Formats a number into a string according to a unit definition for a locale.

  During processing any `:format_options` of a `Unit.t()` are merged with
  `options` with `options` taking precedence.

  ## Arguments

  * `list_or_number` is any number (integer, float or Decimal) or a
    `t:Cldr.Unit` struct or a list of `t:Cldr.Unit` structs

  * `backend` is any module that includes `use Cldr` and therefore
    is a `Cldr` backend module. The default is `Cldr.default_backend!/0`.

  * `options` is a keyword list of options.

  ## Options

  * `:unit` is any unit returned by `Cldr.Unit.known_units/0`. Ignored if
    the number to be formatted is a `t:Cldr.Unit` struct

  * `:locale` is any valid locale name returned by `Cldr.known_locale_names/1`
    or a `Cldr.LanguageTag` struct.  The default is `Cldr.get_locale/0`

  * `style` is one of those returned by `Cldr.Unit.known_styles/0`.
    The current styles are `:long`, `:short` and `:narrow`.
    The default is `style: :long`

  * `:grammatical_case` indicates that a localisation for the given
    locale and given grammatical case should be used. See `Cldr.Unit.known_grammatical_cases/0`
    for the list of known grammatical cases. Note that not all locales
    define all cases. However all locales do define the `:nominative`
    case, which is also the default.

  * `:gender` indicates that a localisation for the given
    locale and given grammatical gender should be used.
    See `Cldr.Unit.known_grammatical_genders/0`
    for the list of known grammatical genders. Note that not all locales
    define all genders.

  * `:list_options` is a keyword list of options for formatting a list
    which is passed through to `Cldr.List.to_string/3`. This is only
    applicable when formatting a list of units.

  * Any other options are passed to `Cldr.Number.to_string/2`
    which is used to format the `number`

  ## Returns

  * `{:ok, formatted_string}` or

  * `{:error, {exception, message}}`

  ## Examples

      iex> Cldr.Unit.Format.to_string Cldr.Unit.new!(:gallon, 123), MyApp.Cldr
      {:ok, "123 gallons"}

      iex> Cldr.Unit.Format.to_string Cldr.Unit.new!(:gallon, 1), MyApp.Cldr
      {:ok, "1 gallon"}

      iex> Cldr.Unit.Format.to_string Cldr.Unit.new!(:gallon, 1), MyApp.Cldr, locale: "af"
      {:ok, "1 gelling"}

      iex> Cldr.Unit.Format.to_string Cldr.Unit.new!(:gallon, 1), MyApp.Cldr, locale: "bs"
      {:ok, "1 galon"}

      iex> Cldr.Unit.Format.to_string Cldr.Unit.new!(:gallon, 1234), MyApp.Cldr, format: :long
      {:ok, "1 thousand gallons"}

      iex> Cldr.Unit.Format.to_string Cldr.Unit.new!(:gallon, 1234), MyApp.Cldr, format: :short
      {:ok, "1K gallons"}

      iex> Cldr.Unit.Format.to_string Cldr.Unit.new!(:megahertz, 1234), MyApp.Cldr
      {:ok, "1,234 megahertz"}

      iex> Cldr.Unit.Format.to_string Cldr.Unit.new!(:megahertz, 1234), MyApp.Cldr, style: :narrow
      {:ok, "1,234MHz"}

      iex> Cldr.Unit.Format.to_string Cldr.Unit.new!(123, :foot), MyApp.Cldr
      {:ok, "123 feet"}

      iex> Cldr.Unit.Format.to_string 123, MyApp.Cldr, unit: :foot
      {:ok, "123 feet"}

      iex> Cldr.Unit.Format.to_string Decimal.new(123), MyApp.Cldr, unit: :foot
      {:ok, "123 feet"}

      iex> Cldr.Unit.Format.to_string 123, MyApp.Cldr, unit: :megabyte, locale: "en", style: :unknown
      {:error, {Cldr.UnknownFormatError, "The unit style :unknown is not known."}}

      iex> Cldr.Unit.Format.to_string 123, MyApp.Cldr, unit: :megabyte, locale: "en",
      ...> grammatical_gender: :feminine
      {:error, {Cldr.UnknownGrammaticalGenderError,
        "The locale \\"en\\" does not define a grammatical gender :feminine. The valid genders are [:masculine]"
      }}

  """

  @spec to_string(
          Unit.value() | Unit.t() | list(Unit.t()),
          Cldr.backend() | Keyword.t(),
          Keyword.t()
        ) ::
          {:ok, String.t()} | {:error, {atom, binary}}

  def to_string(list_or_unit, backend, options \\ [])

  # Options but no backend
  def to_string(list_or_unit, options, []) when is_list(options) do
    locale = Cldr.get_locale()
    to_string(list_or_unit, locale.backend, options)
  end

  # It's a list of units so we format each of them
  # and combine the list
  def to_string(unit_list, backend, options) when is_list(unit_list) do
    with {:ok, options} <- normalize_options(backend, options) do
      list_options =
        options
        |> Keyword.get(:list_options, [])
        |> Keyword.put(:locale, options[:locale])

      unit_list
      |> Enum.map(&to_string!(&1, backend, options))
      |> Cldr.List.to_string(backend, list_options)
    end
  end

  # It's a number, not a unit struct
  def to_string(number, backend, options) when is_number(number) do
    with {:ok, unit} <- Cldr.Unit.new(options[:unit], number) do
      to_string(unit, backend, options)
    end
  end

  def to_string(%Decimal{} = number, backend, options) do
    with {:ok, unit} <- Cldr.Unit.new(options[:unit], number) do
      to_string(unit, backend, options)
    end
  end

  # Now we have a unit, a backend and some options but ratio
  # values need to be converted to decimals
  def to_string(%Unit{value: %Ratio{}} = unit, backend, options) when is_list(options) do
    unit = Cldr.Unit.to_decimal_unit(unit)
    to_string(unit, backend, options)
  end

  def to_string(%Unit{} = unit, backend, options) when is_list(options) do
    with {:ok, options} <- normalize_options(backend, options),
         {:ok, list} <- to_iolist(unit, backend, options) do
      list
      |> :erlang.iolist_to_binary()
      # |> String.replace(~r/([\s])+/, "\\1")
      |> wrap(:ok)
    end
  end

  @doc """
  Formats a number into a string according to a unit definition
  for the current process's locale and backend or raises
  on error.

  The curent process's locale is set with
  `Cldr.put_locale/1`.

  See `Cldr.Unit.to_string!/3` for full details.

  """
  @spec to_string!(list_or_number :: Unit.value() | Unit.t() | [Unit.t()]) ::
          String.t() | no_return()

  def to_string!(unit) do
    locale = Cldr.get_locale()
    backend = locale.backend
    to_string!(unit, backend, locale: locale)
  end

  @doc """
  Formats a number into a string according to a unit definition
  for the current process's locale and backend or raises
  on error.

  During processing any `:format_options` of a `t:Cldr.Unit` are merged with
  `options` with `options` taking precedence.

  ## Arguments

  * `number` is any number (integer, float or Decimal) or a
    `t:Cldr.Unit` struct

  * `backend` is any module that includes `use Cldr` and therefore
    is a `Cldr` backend module. The default is `Cldr.default_backend!/0`.

  * `options` is a keyword list

  ## Options

  * `:unit` is any unit returned by `Cldr.Unit.known_units/0`. Ignored if
    the number to be formatted is a `t:Cldr.Unit` struct

  * `:locale` is any valid locale name returned by `Cldr.known_locale_names/0`
    or a `Cldr.LanguageTag` struct.  The default is `Cldr.get_locale/0`

  * `:style` is one of those returned by `Cldr.Unit.available_styles`.
    The current styles are `:long`, `:short` and `:narrow`.
    The default is `style: :long`

  * Any other options are passed to `Cldr.Number.to_string/2`
    which is used to format the `number`

  ## Returns

  * `formatted_string` or

  * raises an exception

  ## Examples

      iex> Cldr.Unit.Format.to_string! Cldr.Unit.new!(:gallon, 123), MyApp.Cldr
      "123 gallons"

      iex> Cldr.Unit.Format.to_string! Cldr.Unit.new!(:gallon, 1), MyApp.Cldr
      "1 gallon"

      iex> Cldr.Unit.Format.to_string! Cldr.Unit.new!(:gallon, 1), MyApp.Cldr, locale: "af"
      "1 gelling"

  """
  @spec to_string!(
          Unit.value() | Unit.t() | list(Unit.t()),
          Cldr.backend() | Keyword.t(),
          Keyword.t()
        ) ::
          String.t() | no_return()

  def to_string!(unit, backend, options \\ []) do
    case to_string(unit, backend, options) do
      {:ok, string} -> string
      {:error, {exception, message}} -> raise exception, message
    end
  end

  defp normalize_options(backend, options) do
    {locale, backend} = Cldr.locale_and_backend_from(options[:locale], backend)
    unit_backend = Module.concat(backend, :Unit)
    style = Keyword.get(options, :style, @default_style)
    grammatical_case = Keyword.get(options, :grammatical_case, @default_case)
    grammatical_gender = Keyword.get(options, :grammatical_gender)

    with {:ok, locale} <- Cldr.validate_locale(locale, backend),
         {:ok, grammatical_case} <- Cldr.Unit.validate_grammatical_case(grammatical_case),
         {:ok, default_gender} <- unit_backend.default_gender(locale),
         {:ok, gender} <-
           Cldr.Unit.validate_grammatical_gender(grammatical_gender, default_gender, locale),
         {:ok, style} <- Cldr.Unit.validate_style(style) do
      options
      |> Keyword.put(:locale, locale)
      |> Keyword.put(:style, style)
      |> Keyword.put(:grammatical_case, grammatical_case)
      |> Keyword.put(:grammatical_gender, gender)
      |> wrap(:ok)
    end
  end

  @doc """
  Formats a number into an iolist according to a unit definition
  for the current process's locale and backend.

  The curent process's locale is set with
  `Cldr.put_locale/1`.

  See `Cldr.Unit.Format.to_iolist/3` for full details.

  """
  @spec to_iolist(list_or_number :: Unit.value() | Unit.t() | [Unit.t()]) ::
          {:ok, String.t()} | {:error, {atom, binary}}

  def to_iolist(unit) do
    locale = Cldr.get_locale()
    backend = locale.backend
    to_iolist(unit, backend, locale: locale)
  end

  @doc """
  Formats a number into an iolist according to a unit definition
  for a locale.

  ## Arguments

  * `list_or_number` is any number (integer, float or Decimal) or a
    `t:Cldr.Unit` struct or a list of `t:Cldr.Unit` structs

  * `options` is a keyword list

  ## Options

  * `:unit` is any unit returned by `Cldr.Unit.known_units/0`. Ignored if
    the number to be formatted is a `t:Cldr.Unit` struct

  * `:locale` is any valid locale name returned by `Cldr.known_locale_names/0`
    or a `Cldr.LanguageTag` struct.  The default is `Cldr.get_locale/0`

  * `:style` is one of those returned by `Cldr.Unit.available_styles`.
    The current styles are `:long`, `:short` and `:narrow`.
    The default is `style: :long`

  * `:grammatical_case` indicates that a localisation for the given
    locale and given grammatical case should be used. See `Cldr.Unit.known_grammatical_cases/0`
    for the list of known grammatical cases. Note that not all locales
    define all cases. However all locales do define the `:nominative`
    case, which is also the default.

  * `:gender` indicates that a localisation for the given
    locale and given grammatical gender should be used. See `Cldr.Unit.known_grammatical_genders/0`
    for the list of known grammatical genders. Note that not all locales
    define all genders.

  * `:list_options` is a keyword list of options for formatting a list
    which is passed through to `Cldr.List.to_string/3`. This is only
    applicable when formatting a list of units.

  * Any other options are passed to `Cldr.Number.to_string/2`
    which is used to format the `number`

  ## Returns

  * `{:ok, io_list}` or

  * `{:error, {exception, message}}`

  ## Examples

      iex> Cldr.Unit.Format.to_iolist Cldr.Unit.new!(:gallon, 123)
      {:ok, ["123", " gallons"]}

  """
  @spec to_iolist(Cldr.Unit.value() | Cldr.Unit.t() | [Cldr.Unit.t(), ...], Keyword.t()) ::
          {:ok, list()} | {:error, {atom, binary}}

  def to_iolist(unit, backend, options \\ [])

  # Options but no backend
  def to_iolist(list_or_unit, options, []) when is_list(options) do
    {_locale, backend} = Cldr.locale_and_backend_from(options)
    to_iolist(list_or_unit, backend, options)
  end

  # Direct formatting of the unit since
  # it is translatable directly
  def to_iolist(%Cldr.Unit{unit: name} = unit, backend, options) when name in @translatable_units do
    {locale, format, grammatical_case, gender, plural, _per_plural} =
      extract_options!(unit, options)

    formats = Cldr.Unit.units_for(locale, format, backend)
    number_format_options = Keyword.merge(unit.format_options, options)
    unit_grammar = {name, {grammatical_case, plural}}

    formatted_number = format_number!(unit, backend, number_format_options)
    unit_pattern = get_unit_pattern!(unit, unit_grammar, formats, grammatical_case, gender, plural)

    Cldr.Substitution.substitute(formatted_number, unit_pattern)
    |> wrap(:ok)
  end

  def to_iolist(%Cldr.Unit{} = unit, backend, options) do
    {locale, format, grammatical_case, gender, plural, per_plural} = extract_options!(unit, options)

    formats = Cldr.Unit.units_for(locale, format, backend)
    number_format_options = Keyword.merge(unit.format_options, options)
    formatted_number = format_number!(unit, backend, number_format_options)
    grammar = grammar(unit, locale: locale, backend: backend)

    do_iolist(unit, grammar, formatted_number, formats, grammatical_case, gender, plural, per_plural)
    |> wrap(:ok)
  end

  def to_iolist(number, backend, options) when is_number(number) do
    {unit, options} = Keyword.pop(options, :unit)

    with {:ok, unit} <- Cldr.Unit.new(number, unit) do
      to_iolist(unit, backend, options)
    end
  end

  def to_iolist(%Decimal{} = number, backend, options) do
    {unit, options} = Keyword.pop(options, :unit)

    with {:ok, unit} <- Cldr.Unit.new(number, unit) do
      to_iolist(unit, backend, options)
    end
  end

  @doc """
  Formats a number into an iolist according to a unit definition
  for the current process's locale and backend.

  The curent process's locale is set with
  `Cldr.put_locale/1`.

  See `Cldr.Unit.Format.to_iolist!/3` for full details.

  """
  @spec to_iolist!(Cldr.Unit.value() | Cldr.Unit.t() | [Cldr.Unit.t(), ...]) ::
          list() | no_return()

  def to_iolist!(unit) do
    locale = Cldr.get_locale()
    backend = locale.backend
    to_iolist!(unit, backend, locale: locale)
  end

  @doc """
  Formats a unit using `to_iolist/3` but raises if there is
  an error.

  ## Arguments

  * `list_or_number` is any number (integer, float or Decimal) or a
    `t:Cldr.Unit` struct or a list of `t:Cldr.Unit` structs

  * `options` is a keyword list

  ## Options

  * `:unit` is any unit returned by `Cldr.Unit.known_units/0`. Ignored if
    the number to be formatted is a `t:Cldr.Unit` struct

  * `:locale` is any valid locale name returned by `Cldr.known_locale_names/0`
    or a `Cldr.LanguageTag` struct.  The default is `Cldr.get_locale/0`

  * `:style` is one of those returned by `Cldr.Unit.known_styles/0`.
    The current styles are `:long`, `:short` and `:narrow`.
    The default is `style: :long`.

  * `:grammatical_case` indicates that a localisation for the given
    locale and given grammatical case should be used. See `Cldr.Unit.known_grammatical_cases/0`
    for the list of known grammatical cases. Note that not all locales
    define all cases. However all locales do define the `:nominative`
    case, which is also the default.

  * `:gender` indicates that a localisation for the given
    locale and given grammatical gender should be used. See `Cldr.Unit.known_grammatical_genders/0`
    for the list of known grammatical genders. Note that not all locales
    define all genders.

  * `:list_options` is a keyword list of options for formatting a list
    which is passed through to `Cldr.List.to_string/3`. This is only
    applicable when formatting a list of units.

  * Any other options are passed to `Cldr.Number.to_string/2`
    which is used to format the `number`

  ## Returns

  * `io_list` or

  * raises an exception

  ## Examples

      iex> Cldr.Unit.Format.to_iolist! 123, unit: :gallon
      ["123", " gallons"]

  """
  @spec to_iolist!(Cldr.Unit.value() | Cldr.Unit.t() | [Cldr.Unit.t(), ...], Keyword.t()) ::
          list() | no_return()

  def to_iolist!(number, backend, options \\ [])

  def to_iolist!(list_or_unit, options, []) when is_list(options) do
    {_locale, backend} = Cldr.locale_and_backend_from(options)
    to_iolist!(list_or_unit, backend, options)
  end

  def to_iolist!(number, backend, options) do
    case to_iolist(number, backend, options) do
      {:ok, io_list} -> io_list
      {:error, {exception, reason}} -> raise exception, reason
    end
  end

  ##
  ##
  ## Implementation details
  ##
  ##

  # For the numerator of a unit
  defp do_iolist(unit, grammar, formatted_number, formats, grammatical_case, gender, plural, _per_plural)
       when is_list(grammar) do
    unit
    |> do_iolist(grammar, formats, grammatical_case, gender, plural)
    |> substitute_number(formatted_number)
  end

  # For compound "per" units
  defp do_iolist(unit, grammar, formatted_number, formats, grammatical_case, gender, plural, per_plural) do
    {numerator, denominator} = grammar

    per_pattern = get_in(formats, [:per, :compound_unit_pattern])

    numerator_pattern =
      do_iolist(unit, numerator, formatted_number, formats, grammatical_case, gender, plural, per_plural)

    denominator_pattern =
      do_iolist(unit, denominator, formats, grammatical_case, gender, per_plural)
      |> extract_unit

    Cldr.Substitution.substitute([numerator_pattern, denominator_pattern], per_pattern)
  end

  # Recurive processing of a unit grammar
  defp do_iolist(_unit, [], _formats, _grammatical_case, _gender, _plural) do
    []
  end

  # SI Prefixes
  defp do_iolist(unit, [{si_prefix, _} | rest], formats, grammatical_case, gender, plural)
       when si_prefix in @si_keys do
    si_pattern = get_si_pattern!(formats, si_prefix, grammatical_case, gender, plural)
    rest = do_iolist(unit, rest, formats, grammatical_case, gender, plural)
    merge_SI_prefix(si_pattern, rest)
  end

  # Power prefixes
  defp do_iolist(unit, [{power_prefix, _} | rest], formats, grammatical_case, gender, plural)
       when power_prefix in @power_keys do
    power_pattern = get_power_pattern!(formats, power_prefix, grammatical_case, gender, plural)

    rest = do_iolist(unit, rest, formats, grammatical_case, gender, plural)
    merge_power_prefix(power_pattern, rest)
  end

  defp do_iolist(unit, [first], formats, grammatical_case, gender, plural) when is_grammar(first) do
    get_unit_pattern!(unit, first, formats, grammatical_case, gender, plural)
  end

  defp do_iolist(_unit, [pattern_list], _formats, _grammatical_case, _gender, _plural) do
    pattern_list
  end

  # List head is a grammar unit
  defp do_iolist(unit, [first | rest], formats, grammatical_case, gender, plural) when is_grammar(first) do
    times_pattern = get_in(formats, [:times, :compound_unit_pattern])

    unit_pattern_1 = get_unit_pattern!(unit, first, formats, grammatical_case, gender, plural)

    unit_pattern_2 =
      do_iolist(unit, rest, formats, grammatical_case, gender, plural)
      |> extract_unit()

    Cldr.Substitution.substitute([unit_pattern_1, unit_pattern_2], times_pattern)
  end

  # List head is a format pattern
  @dialyzer {:nowarn_function, do_iolist: 6}

  defp do_iolist(unit, [unit_pattern_1 | rest], formats, grammatical_case, gender, plural) do
    times_pattern = get_in(formats, [:times, :compound_unit_pattern])

    unit_pattern_2 =
      do_iolist(unit, rest, formats, grammatical_case, gender, plural)
      |> extract_unit()

    Cldr.Substitution.substitute([unit_pattern_1, unit_pattern_2], times_pattern)
  end

  # Get the appropriate unit pattern. An important part of
  # this is the following from TR35:

  # Note that for certain plural cases, the unit pattern may not
  # provide for inclusion of a numeric value—that is, it may not
  # include “{0}”. This is especially true for the explicit cases
  # “0” and “1” (which may have patterns like “zero seconds”). In
  # certain languages such as Arabic and Hebrew, this may also be
  # true with certain units for the plural cases “zero”, “one”, or
  # “two” (in these languages, such plural cases are only used for
  # the corresponding exact numeric values, so there is no concern
  # about loss of precision without the numeric value).

  # Therefore the overall proess is as follows:
  #
  # If there is a tenplate for an explicit value, try that template.
  # as of CLDR39 there are no locales that have any explicit cases
  # but a custom unit may have such data.

  # If there is no such value then proceed with the
  # provided plural category

  # If however the retrieved pattern has no substitutions
  # then that pattern is only used if there is an exacf match
  # with the value. This means that if the pattern has no
  # substitutions for the plural category `:one` then it
  # is applied only if the the unit value is "1". Otherwise
  # use the unit category `:other`.

  defp get_unit_pattern!(%Unit{} = unit, grammar, formats, grammatical_case, gender, plural) do
    integer = integer_unit_value(unit)
    integer_pattern = get_unit_pattern(grammar, formats, grammatical_case, gender, integer)

    cond do
      # If the pattern for an integer is found, use it
      integer_pattern ->
        integer_pattern
        # |> IO.inspect(label: "Integer pattern")

      # If the plural range and the integer are aligned, use the plural
      # rule no matter whether it has substitutions
      integer_and_plural_match?(integer, plural) ->
        get_unit_pattern(grammar, formats, grammatical_case, gender, plural) ||
        get_unit_pattern(grammar, formats, grammatical_case, gender, @default_plural)


      # For these plurals get the template and use it only
      # if it has substitutions. If it doesn't then use the default
      # pattern
      plural in [:zero, :one, :two] ->
        pattern = get_unit_pattern(grammar, formats, grammatical_case, gender, plural)

        if has_substitutions?(pattern) do
          pattern
        else
          get_unit_pattern(grammar, formats, grammatical_case, gender, :force_default)
        end

      # For all other cases return the pattern for the given plural
      # category or the default.
      true ->
        get_unit_pattern(grammar, formats, grammatical_case, gender, plural) ||
        get_unit_pattern(grammar, formats, grammatical_case, gender, @default_plural)
    end
    || raise Cldr.Unit.NoPatternError, {unit, grammatical_case, gender, plural}
  end

  defp get_unit_pattern(grammar, formats, grammatical_case, _gender, plural) when is_integer(plural) do
    {name, {unit_case, _unit_plural}} = grammar
    unit_case = if unit_case == :compound, do: grammatical_case, else: unit_case

    get_in(formats, [name, unit_case, plural]) ||
      get_in(formats, [name, @default_case, plural])
  end

  defp get_unit_pattern(grammar, formats, grammatical_case, _gender, :force_default) do
    {name, {unit_case, _unit_plural}} = grammar
    unit_case = if unit_case == :compound, do: grammatical_case, else: unit_case

    get_in(formats, [name, unit_case, @default_plural]) ||
      get_in(formats, [name, @default_case, @default_plural])
  end

  defp get_unit_pattern(grammar, formats, grammatical_case, _gender, plural) do
    {name, {unit_case, unit_plural}} = grammar
    unit_case = if unit_case == :compound, do: grammatical_case, else: unit_case
    unit_plural = if unit_plural == :compound, do: plural, else: unit_plural

    get_in(formats, [name, unit_case, unit_plural]) ||
      get_in(formats, [name, @default_case, unit_plural]) ||
      get_in(formats, [name, unit_case, @default_plural]) ||
      get_in(formats, [name, @default_case, @default_plural])
  end

  defp get_si_pattern!(formats, si_prefix, grammatical_case, gender, plural) do
    get_in(formats, [si_prefix, :unit_prefix_pattern]) ||
      raise(Cldr.Unit.NoPatternError, {si_prefix, grammatical_case, gender, plural})
  end

  defp get_power_pattern!(formats, power_prefix, grammatical_case, gender, plural) do
    power_formats = get_in(formats, [power_prefix, :compound_unit_pattern])

    get_in(power_formats, [gender, plural, grammatical_case]) ||
      get_in(power_formats, [gender, plural]) ||
      get_in(power_formats, [plural, grammatical_case]) ||
      get_in(power_formats, [plural]) ||
      get_in(power_formats, [@default_case]) ||
      raise(Cldr.Unit.NoPatternError, {power_prefix, grammatical_case, gender, plural})
  end

  defp integer_and_plural_match?(0, :zero), do: true
  defp integer_and_plural_match?(1, :one), do: true
  defp integer_and_plural_match?(2, :two), do: true
  defp integer_and_plural_match?(_, _), do: false

  defp has_substitutions?(pattern) when is_list(pattern) and length(pattern) > 1, do: true
  defp has_substitutions?(pattern) when is_list(pattern), do: false

  defp extract_unit([place, string]) when is_integer(place) do
    String.trim(string)
  end

  defp extract_unit([string, place]) when is_integer(place) do
    String.trim(string)
  end

  defp extract_unit([unit | rest]) do
    [extract_unit(unit) | rest]
  end

  defp extract_unit(other) do
    other
  end

  defp format_number!(unit, backend, options) do
    number_format_options = Keyword.merge(unit.format_options, options)
    Cldr.Number.to_string!(unit.value, backend, number_format_options)
  end

  defp substitute_number([place, unit], formatted_number) when is_integer(place) do
    Cldr.Substitution.substitute(formatted_number, [place, unit])
  end

  defp substitute_number([unit, place], formatted_number) when is_integer(place) do
    Cldr.Substitution.substitute(formatted_number, [place, unit])
  end

  defp substitute_number([head | rest], formatted_number) when is_list(rest) do
    [Cldr.Substitution.substitute(formatted_number, head) | rest]
  end

  # Merging power and SI prefixes into a pattern is a heuristic since the
  # underlying data does not convey those rules.

  @merge_SI_prefix ~r/([^\s]+)$/u
  defp merge_SI_prefix([prefix, place], [place, string]) when is_integer(place) do
    string = maybe_downcase(prefix, string)
    [place, String.replace(string, @merge_SI_prefix, "#{prefix}\\1")]
  end

  defp merge_SI_prefix([prefix, place], [string, place]) when is_integer(place) do
    string = maybe_downcase(prefix, string)
    [String.replace(string, @merge_SI_prefix, "#{prefix}\\1"), place]
  end

  defp merge_SI_prefix([place, prefix], [place, string]) when is_integer(place) do
    string = maybe_downcase(prefix, string)
    [place, String.replace(string, @merge_SI_prefix, "#{prefix}\\1")]
  end

  defp merge_SI_prefix([place, prefix], [string, place]) when is_integer(place) do
    string = maybe_downcase(prefix, string)
    [String.replace(string, @merge_SI_prefix, "#{prefix}\\1"), place]
  end

  defp merge_SI_prefix(prefix_pattern, [unit_pattern | rest]) do
    [merge_SI_prefix(prefix_pattern, unit_pattern) | rest]
  end

  @merge_power_prefix ~r/([^\s]+)/u
  defp merge_power_prefix([prefix, place], [place, string]) when is_integer(place) do
    [place, String.replace(string, @merge_power_prefix, "#{prefix}\\1")]
  end

  defp merge_power_prefix([prefix, place], [string, place]) when is_integer(place) do
    [String.replace(string, @merge_power_prefix, "#{prefix}\\1"), place]
  end

  defp merge_power_prefix([place, prefix], [place, string]) when is_integer(place) do
    [place, String.replace(string, @merge_power_prefix, "\\1#{prefix}")]
  end

  defp merge_power_prefix([place, prefix], [string, place]) when is_integer(place) do
    [String.replace(string, @merge_power_prefix, "\\1#{prefix}"), place]
  end

  defp merge_power_prefix([place, prefix], list) when is_integer(place) and is_list(list) do
    [list, prefix]
  end

  defp merge_power_prefix([prefix, place], [string | rest]) when is_integer(place) do
    string = maybe_downcase(prefix, string)
    [prefix, [string | rest]]
  end

  defp merge_power_prefix([prefix, place], string) when is_integer(place) and is_binary(string) do
    string = maybe_downcase(prefix, string)
    [prefix, string]
  end

  # If the prefix has no trailing whitespace then
  # downcase the string since it will be
  # joined adjacent to the prefix
  defp maybe_downcase(prefix, string) do
    if String.match?(prefix, ~r/\s+$/u) do
      string
    else
      String.downcase(string)
    end
  end

  @per_plural_default :one

  defp extract_options!(unit, options) do
    {locale, backend} = Cldr.locale_and_backend_from(options)
    unit_backend = Module.concat(backend, :Unit)

    format = Keyword.get(options, :style, @default_style)
    grammatical_case = Keyword.get(options, :grammatical_case, @default_case)
    gender = Keyword.get(options, :grammatical_gender, unit_backend.default_gender(locale))
    plural = Cldr.Number.PluralRule.plural_type(unit.value, backend, locale: locale)

    per_plural =
      locale
      |> unit_backend.grammatical_features()
      |> get_in([:plural, :per, 1])

    {locale, format, grammatical_case, gender, plural, per_plural || @per_plural_default}
  end

  @doc false
  def wrap(term, tag) do
    {tag, term}
  end

  @doc """
  Traverses the components of a unit
  and resolves a list of base units with
  their gramatical case and plural selector
  definitions for a given locale.

  This function relies upon the internal
  representation of units and grammatical features
  and is primarily for the support of
  formatting a function through `Cldr.Unit.to_string/2`.

  ## Arguments

  * `unit` is a `t:Cldr.Unit` or a binary
    unit string

  ## Options

  * `:locale` is any valid locale name returned by `Cldr.known_locale_names/1`
    or a `t:Cldr.LanguageTag` struct.  The default is `Cldr.get_locale/0`

  * `backend` is any module that includes `use Cldr` and therefore
    is a `Cldr` backend module. The default is `Cldr.default_backend!/0`.

  ## Returns

  ## Examples

  """
  @doc since: "3.5.0"
  @spec grammar(Unit.t(), Keyword.t()) :: grammar_list() | {grammar_list(), grammar_list()}

  def grammar(unit, options \\ [])

  def grammar(%Unit{} = unit, options) do
    {locale, backend} = Cldr.locale_and_backend_from(options)
    module = Module.concat(backend, :Unit)

    features =
      module.grammatical_features("root")
      |> Map.merge(module.grammatical_features(locale))

    grammatical_case = Map.fetch!(features, :case)
    plural = Map.fetch!(features, :plural)

    traverse(unit, &grammar(&1, grammatical_case, plural, options))
  end

  def grammar(unit, options) when is_binary(unit) do
    grammar(Unit.new!(1, unit), options)
  end

  defp grammar({:unit, unit}, _grammatical_case, _plural, _options) do
    {unit, {:compound, :compound}}
  end

  defp grammar({:per, {left, right}}, _grammatical_case, _plural, _options)
       when is_list(left) and is_list(right) do
    {left, right}
  end

  defp grammar({:per, {left, {right, _}}}, grammatical_case, plural, _options) when is_list(left) do
    {left, [{right, {grammatical_case.per[1], plural.per[1]}}]}
  end

  defp grammar({:per, {{left, _}, right}}, grammatical_case, plural, _options)
       when is_list(right) do
    {[{left, {grammatical_case.per[0], plural.per[0]}}], right}
  end

  defp grammar({:per, {{left, _}, {right, _}}}, grammatical_case, plural, _options) do
    {[{left, {grammatical_case.per[0], plural.per[0]}}],
     [{right, {grammatical_case.per[1], plural.per[1]}}]}
  end

  defp grammar({:times, {left, right}}, _grammatical_case, _plural, _options)
       when is_list(left) and is_list(right) do
    left ++ right
  end

  defp grammar({:times, {{left, _}, right}}, grammatical_case, plural, _options)
       when is_list(right) do
    [{left, {grammatical_case.times[0], plural.times[0]}} | right]
  end

  defp grammar({:times, {left, {right, _}}}, grammatical_case, plural, _options)
       when is_list(left) do
    left ++ [{right, {grammatical_case.times[1], plural.times[1]}}]
  end

  defp grammar({:times, {{left, _}, {right, _}}}, grammatical_case, plural, _options) do
    [
      {left, {grammatical_case.times[0], plural.times[0]}},
      {right, {grammatical_case.times[1], plural.times[1]}}
    ]
  end

  defp grammar({:power, {{left, _}, right}}, grammatical_case, plural, _options)
       when is_list(right) do
    [{left, {grammatical_case.power[0], plural.power[0]}} | right]
  end

  defp grammar({:power, {{left, _}, {right, _}}}, grammatical_case, plural, _options) do
    [
      {left, {grammatical_case.power[0], plural.power[0]}},
      {right, {grammatical_case.power[1], plural.power[1]}}
    ]
  end

  defp grammar({:prefix, {{left, _}, {right, _}}}, grammatical_case, plural, _options) do
    [
      {left, {grammatical_case.prefix[0], plural.prefix[0]}},
      {right, {grammatical_case.prefix[1], plural.prefix[1]}}
    ]
  end

  @doc """
  Traverses a unit's decomposition and invokes
  a function on each node of the composition
  tree.

  ## Arguments

  * `unit` is any unit returned by `Cldr.Unit.new/2`

  * `fun` is any single-arity function. It will be invoked
    for each node of the composition tree. The argument is a tuple
    of the following form:

    * `{:unit, argument}`
    * `{:times, {argument_1, argument_2}}`
    * `{:prefix, {prefix_unit, argument}}`
    * `{:power, {power_unit, argument}}`
    * `{:per, {argument_1, argument_2}}`

    Where the arguments are the results returned
    from the `fun/1`.

  ## Returns

  The result returned from `fun/1`

  """
  def traverse(%Unit{base_conversion: {left, right}}, fun) when is_function(fun) do
    fun.({:per, {do_traverse(left, fun), do_traverse(right, fun)}})
  end

  def traverse(%Unit{base_conversion: conversion}, fun) when is_function(fun) do
    do_traverse(conversion, fun)
  end

  defp do_traverse([{unit, _}], fun) do
    do_traverse(unit, fun)
  end

  defp do_traverse([head | rest], fun) do
    fun.({:times, {do_traverse(head, fun), do_traverse(rest, fun)}})
  end

  defp do_traverse({unit, _}, fun) do
    do_traverse(unit, fun)
  end

  @si_prefix Cldr.Unit.Prefix.si_power_prefixes()
  @power Cldr.Unit.Prefix.power_units() |> Map.new()

  # String decomposition
  for {power, exp} <- @power do
    power_unit = String.to_atom("power#{exp}")

    defp do_traverse(unquote(power) <> "_" <> unit, fun) do
      fun.({:power, {fun.({:unit, unquote(power_unit)}), do_traverse(unit, fun)}})
    end
  end

  for {prefix, exp} <- @si_prefix do
    prefix_unit = String.to_atom("10p#{exp}" |> String.replace("-", "_"))

    defp do_traverse(unquote(prefix) <> unit, fun) do
      fun.(
        {:prefix,
         {fun.({:unit, unquote(prefix_unit)}), fun.({:unit, String.to_existing_atom(unit)})}}
      )
    end
  end

  defp do_traverse(unit, fun) when is_binary(unit) do
    fun.({:unit, String.to_existing_atom(unit)})
  end

  defp do_traverse(unit, fun) when is_atom(unit) do
    fun.({:unit, unit})
  end

  defp integer_unit_value(%Unit{value: value}) when is_integer(value) do
    value
  end

  defp integer_unit_value(%Unit{value: value}) when is_float(value) do
    int_value = trunc(value)
    if int_value == value, do: int_value, else: nil
  end

  defp integer_unit_value(%Unit{value: %Ratio{}} = value) do
    value
    |> Unit.to_float_unit()
    |> integer_unit_value()
  end

  defp integer_unit_value(%Unit{value: %Decimal{}} = value) do
    value
    |> Unit.to_float_unit()
    |> integer_unit_value()
  end
end
