defmodule Mehungry.AndroidBetaInviteTest do
  use Mehungry.DataCase, async: true

  alias Mehungry.Accounts

  describe "android_beta_email_html/1" do
    test "renders the branded invite with the opt-in URL" do
      html = Accounts.android_beta_email_html(opt_in_url: "https://play.google.com/apps/testing/x")

      assert html =~ "Test the Mehungry Android app"
      assert html =~ "Become a tester"
      assert html =~ "https://play.google.com/apps/testing/x"
      # branded shell (dark background + logo wordmark)
      # current brand shell: warm-charcoal ink background + wordmark
      assert html =~ "#17140F"
      assert html =~ "HUNGRY"
    end

    test "falls back to the configured opt-in URL" do
      html = Accounts.android_beta_email_html([])
      assert html =~ Accounts.android_beta_opt_in_url()
    end

    test "escapes an admin-supplied intro" do
      html = Accounts.android_beta_email_html(intro: "<script>alert(1)</script>")

      refute html =~ "<script>alert(1)</script>"
      assert html =~ "&lt;script&gt;"
    end
  end

  describe "deliver_android_beta_invite/2" do
    test "sends a branded invite to the recipient" do
      assert {:ok, email} =
               Accounts.deliver_android_beta_invite("tester@example.com",
                 opt_in_url: "https://play.google.com/apps/testing/x"
               )

      assert {_, "tester@example.com"} = hd(email.to)
      assert email.subject =~ "Android"
      assert email.html_body =~ "https://play.google.com/apps/testing/x"
      assert email.text_body =~ "https://play.google.com/apps/testing/x"
    end
  end

  describe "deliver_trial_welcome/2" do
    test "sends a branded welcome carrying the unsubscribe link" do
      url = "https://www.m3hungry.com/trial/unsubscribe/abc123"

      assert {:ok, email} = Accounts.deliver_trial_welcome("tester@example.com", url)

      assert {_, "tester@example.com"} = hd(email.to)
      assert email.subject =~ "Mehungry"
      assert email.html_body =~ url
      assert email.text_body =~ url
      # branded shell
      assert email.html_body =~ "HUNGRY"
    end
  end
end
