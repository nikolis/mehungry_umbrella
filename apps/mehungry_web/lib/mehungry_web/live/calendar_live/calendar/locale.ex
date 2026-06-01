defmodule MehungryWeb.CalendarLive.Calendar.Locale do
  @moduledoc false

  @days_el %{
    1 => "Δευτέρα",
    2 => "Τρίτη",
    3 => "Τετάρτη",
    4 => "Πέμπτη",
    5 => "Παρασκευή",
    6 => "Σάββατο",
    7 => "Κυριακή"
  }

  @months_el %{
    1 => "Ιανουάριος",
    2 => "Φεβρουάριος",
    3 => "Μάρτιος",
    4 => "Απρίλιος",
    5 => "Μάιος",
    6 => "Ιούνιος",
    7 => "Ιούλιος",
    8 => "Αύγουστος",
    9 => "Σεπτέμβριος",
    10 => "Οκτώβριος",
    11 => "Νοέμβριος",
    12 => "Δεκέμβριος"
  }

  @months_short_el %{
    1 => "Ιαν",
    2 => "Φεβ",
    3 => "Μαρ",
    4 => "Απρ",
    5 => "Μαϊ",
    6 => "Ιουν",
    7 => "Ιουλ",
    8 => "Αυγ",
    9 => "Σεπ",
    10 => "Οκτ",
    11 => "Νοε",
    12 => "Δεκ"
  }

  def day_name(%Date{} = date, "el") do
    Map.fetch!(@days_el, Date.day_of_week(date))
  end

  def day_name(%Date{} = date, _lang) do
    Calendar.strftime(date, "%A")
  end

  def month_name(%Date{} = date, "el") do
    Map.fetch!(@months_el, date.month)
  end

  def month_name(%Date{} = date, _lang) do
    Calendar.strftime(date, "%B")
  end

  def month_short(%Date{} = date, "el") do
    Map.fetch!(@months_short_el, date.month)
  end

  def month_short(%Date{} = date, _lang) do
    String.slice(Calendar.strftime(date, "%b"), 0..2)
  end

  def format_day_header(%Date{} = date, lang) do
    "#{day_name(date, lang)}, #{date.day} #{month_short(date, lang)}"
  end

  def format_nav_header(%Date{} = date, "el") do
    "#{day_name(date, "el")}, #{date.day} #{month_short(date, "el")}"
  end

  def format_nav_header(%Date{} = date, _lang) do
    "#{Calendar.strftime(date, "%A")}, #{String.slice(Calendar.strftime(date, "%d"), 0..2)} #{String.slice(Calendar.strftime(date, "%B"), 0..2)}"
  end
end
