defmodule MehungryWeb.CalendarLive.Calendar.Utils do
  def calculate_initial_date(current_date, width) do
    days = get_days_according_to_width(width)
    beggining_of_week = Date.beginning_of_week(current_date)

    case days do
      0 ->
        current_date

      1 ->
        current_date

      2 ->
        new_date = Date.add(current_date, -1)

        if(beggining_of_week > new_date) do
          beggining_of_week
        else
          new_date
        end

      3 ->
        new_date = Date.add(current_date, -1)

        if(beggining_of_week > new_date) do
          beggining_of_week
        else
          new_date
        end

      4 ->
        new_date = Date.add(current_date, -2)

        if(beggining_of_week > new_date) do
          beggining_of_week
        else
          new_date
        end

      5 ->
        new_date = Date.add(current_date, -2)

        if(beggining_of_week > new_date) do
          beggining_of_week
        else
          new_date
        end

      6 ->
        beggining_of_week

      _ ->
        beggining_of_week
    end
  end

  @doc """
  Returns the total number of days that could be presented in the screen
  ## Examples

      iex> MyApp.Hello.world(:john)
      :ok

  """
  def get_days_according_to_width(width) do
    case width < 700 do
      true ->
        case width < 400 do
          true ->
            0

          false ->
            1
        end

      false ->
        case width > 700 do
          true ->
            case width > 1000 do
              true ->
                case width > 1300 do
                  true ->
                    case width > 1550 do
                      true ->
                        6

                      false ->
                        5
                    end

                  false ->
                    4
                end

              false ->
                2
            end
        end
    end
  end
end
