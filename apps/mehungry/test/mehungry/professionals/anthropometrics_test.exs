defmodule Mehungry.Professionals.AnthropometricsTest do
  use ExUnit.Case, async: true

  alias Mehungry.Professionals.Anthropometrics

  describe "bmi/2" do
    test "computes weight / height² rounded to 1dp" do
      assert Anthropometrics.bmi(1.70, 72.0) == 24.9
    end

    test "nil when an input is missing or non-positive" do
      assert Anthropometrics.bmi(nil, 72.0) == nil
      assert Anthropometrics.bmi(1.70, nil) == nil
      assert Anthropometrics.bmi(0.0, 72.0) == nil
    end
  end

  describe "bmr_kcal/4 (Mifflin–St Jeor)" do
    test "male: 10*kg + 6.25*cm − 5*age + 5" do
      # 800 + 1125 − 150 + 5 = 1780
      assert Anthropometrics.bmr_kcal("male", 30, 1.80, 80.0) == 1780
    end

    test "female: 10*kg + 6.25*cm − 5*age − 161" do
      # 720 + 1062.5 − 170 − 161 = 1451.5 → 1452
      assert Anthropometrics.bmr_kcal("female", 34, 1.70, 72.0) == 1452
    end

    test "nil when sex unknown or an input missing" do
      assert Anthropometrics.bmr_kcal("other", 30, 1.80, 80.0) == nil
      assert Anthropometrics.bmr_kcal("male", nil, 1.80, 80.0) == nil
      assert Anthropometrics.bmr_kcal("male", 30, nil, 80.0) == nil
    end
  end

  describe "tdee_kcal/2" do
    test "multiplies BMR by the activity factor for every level" do
      assert Anthropometrics.tdee_kcal(1780, "sedentary") == 2136
      assert Anthropometrics.tdee_kcal(1780, "light") == round(1780 * 1.375)
      assert Anthropometrics.tdee_kcal(1780, "moderate") == round(1780 * 1.55)
      assert Anthropometrics.tdee_kcal(1780, "active") == round(1780 * 1.725)
      assert Anthropometrics.tdee_kcal(1780, "very_active") == round(1780 * 1.9)
    end

    test "nil when BMR missing or activity level unknown" do
      assert Anthropometrics.tdee_kcal(nil, "moderate") == nil
      assert Anthropometrics.tdee_kcal(1780, "bogus") == nil
      assert Anthropometrics.tdee_kcal(1780, nil) == nil
    end
  end

  describe "compute/1" do
    test "returns all three when inputs suffice (string or atom keys)" do
      assert Anthropometrics.compute(%{
               height_m: 1.80,
               weight_kg: 80.0,
               sex: "male",
               age: 30,
               activity_level: "sedentary"
             }) == %{bmi: 24.7, bmr_kcal: 1780, tdee_kcal: 2136}

      # string keys + string numbers (form params)
      assert Anthropometrics.compute(%{
               "height_m" => "1.80",
               "weight_kg" => "80",
               "sex" => "male",
               "age" => "30",
               "activity_level" => "sedentary"
             }) == %{bmi: 24.7, bmr_kcal: 1780, tdee_kcal: 2136}
    end

    test "omits keys it cannot compute" do
      # only height+weight → BMI only
      assert Anthropometrics.compute(%{height_m: 1.80, weight_kg: 80.0}) == %{bmi: 24.7}

      # BMR present but no activity → no TDEE
      assert Anthropometrics.compute(%{height_m: 1.80, weight_kg: 80.0, sex: "male", age: 30}) ==
               %{bmi: 24.7, bmr_kcal: 1780}

      assert Anthropometrics.compute(%{}) == %{}
    end
  end
end
