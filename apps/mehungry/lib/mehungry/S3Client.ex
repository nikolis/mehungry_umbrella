defmodule Mehungry.S3Client do
  @moduledoc """
  A module for interacting with AWS S3 using the aws-elixir library.
  Provides functions for common S3 operations like listing buckets,
  uploading, downloading, and deleting objects.
  """

  # Define the AWS region
  @region "eu-central-1"

  @doc """
  Lists all buckets in your AWS account.

  ## Examples

      iex> MyApp.S3Client.list_buckets()
      {:ok, [%{name: "my-bucket", creation_date: ~N[2023-01-01 12:00:00]}]}

  """
  def list_buckets do
    AWS.S3.list_buckets()
    |> AWS.request()
    |> case do
      {:ok, %{body: %{buckets: buckets}}} -> {:ok, buckets}
      error -> {:error, error}
    end
  end

  @doc """
  Creates a new bucket in S3.

  ## Parameters

    - bucket_name: String name of the bucket to create

  ## Examples

      iex> MyApp.S3Client.create_bucket("my-new-bucket")
      {:ok, %{location: "/my-new-bucket"}}

  """
  def create_bucket(bucket_name) do
    AWS.S3.put_bucket(bucket_name)
    |> AWS.request()
    |> case do
      {:ok, response} -> {:ok, response}
      error -> {:error, error}
    end
  end

  @doc """
  Lists objects in a bucket.

  ## Parameters

    - bucket_name: String name of the bucket
    - prefix: Optional string to filter objects by prefix

  ## Examples

      iex> MyApp.S3Client.list_objects("my-bucket", "images/")
      {:ok, [%{key: "images/photo1.jpg", size: 12345, last_modified: ~N[2023-01-01 12:00:00]}]}

  """
  def list_objects(bucket_name, prefix \\ nil) do
    params = if prefix, do: %{"prefix" => prefix}, else: %{}

    AWS.S3.list_objects_v2(bucket_name, params)
    |> AWS.request()
    |> case do
      {:ok, %{body: %{contents: contents}}} -> {:ok, contents}
      error -> {:error, error}
    end
  end

  @doc """
  Uploads a file to S3 from a local path.

  ## Parameters

    - bucket_name: String name of the bucket
    - key: String path/name of the file in S3
    - file_path: Local path to the file to upload
    - content_type: Optional MIME type of the file

  ## Examples

      iex> MyApp.S3Client.upload_file("my-bucket", "images/photo.jpg", "/path/to/local/photo.jpg", "image/jpeg")
      {:ok, %{etag: "\"abcdef1234567890\""}}

  """
  def upload_file(bucket_name, key, file_path, content_type \\ nil) do
    with {:ok, file_binary} <- File.read(file_path),
         headers = build_headers(content_type) do
      AWS.S3.put_object(bucket_name, key, file_binary, headers)
      |> AWS.request()
      |> case do
        {:ok, response} -> {:ok, response}
        error -> {:error, error}
      end
    else
      error -> {:error, error}
    end
  end

  @doc """
  Uploads binary data to S3.

  ## Parameters

    - bucket_name: String name of the bucket
    - key: String path/name of the file in S3
    - data: Binary data to upload
    - content_type: Optional MIME type of the data

  ## Examples

      iex> data = "Hello, World!"
      iex> MyApp.S3Client.upload_binary("my-bucket", "hello.txt", data, "text/plain")
      {:ok, %{etag: "\"abcdef1234567890\""}}

  """
  def upload_binary(bucket_name, key, data, content_type \\ nil) do
    headers = build_headers(content_type)

    AWS.S3.put_object(bucket_name, key, data, headers)
    |> AWS.request()
    |> case do
      {:ok, response} -> {:ok, response}
      error -> {:error, error}
    end
  end

  @doc """
  Downloads a file from S3.

  ## Parameters

    - bucket_name: String name of the bucket
    - key: String path/name of the file in S3

  ## Examples

      iex> MyApp.S3Client.download_file("my-bucket", "documents/report.pdf")
      {:ok, %{body: <<binary_data>>, headers: [{"content-type", "application/pdf"}, ...]}}

  """
  def download_file(bucket_name, key) do
    AWS.S3.get_object(bucket_name, key)
    |> AWS.request()
    |> case do
      {:ok, response} -> {:ok, response}
      error -> {:error, error}
    end
  end

  @doc """
  Downloads a file from S3 and saves it to a local path.

  ## Parameters

    - bucket_name: String name of the bucket
    - key: String path/name of the file in S3
    - destination_path: Local path where the file should be saved

  ## Examples

      iex> MyApp.S3Client.download_file_to_path("my-bucket", "documents/report.pdf", "/local/path/report.pdf")
      {:ok, "/local/path/report.pdf"}

  """
  def download_file_to_path(bucket_name, key, destination_path) do
    case download_file(bucket_name, key) do
      {:ok, %{body: body}} ->
        case File.write(destination_path, body) do
          :ok -> {:ok, destination_path}
          error -> {:error, error}
        end

      error ->
        error
    end
  end

  @doc """
  Deletes an object from S3.

  ## Parameters

    - bucket_name: String name of the bucket
    - key: String path/name of the file in S3

  ## Examples

      iex> MyApp.S3Client.delete_object("my-bucket", "old-file.txt")
      {:ok, %{}}

  """
  def delete_object(bucket_name, key) do
    AWS.S3.delete_object(bucket_name, key)
    |> AWS.request()
    |> case do
      {:ok, response} -> {:ok, response}
      error -> {:error, error}
    end
  end

  @doc """
  Generates a pre-signed URL for temporary access to an S3 object.

  ## Parameters

    - bucket_name: String name of the bucket
    - key: String path/name of the file in S3
    - expires_in: Number of seconds until the URL expires (default: 3600)
    - method: HTTP method to use for the URL (default: :get)

  ## Examples

      iex> MyApp.S3Client.generate_presigned_url("my-bucket", "private/file.jpg", 3600)
      {:ok, "https://my-bucket.s3.amazonaws.com/private/file.jpg?X-Amz-Algorithm=..."}

  """
  def generate_presigned_url(bucket_name, key, expires_in \\ 3600, method \\ :get) do
    operation = build_presign_operation(method, bucket_name, key)

    case AWS.Util.presign_url(operation, expires_in: expires_in) do
      {:ok, url} -> {:ok, url}
      error -> {:error, error}
    end
  end

  @doc """
  Gets the metadata for an S3 object without downloading its content.

  ## Parameters

    - bucket_name: String name of the bucket
    - key: String path/name of the file in S3

  ## Examples

      iex> MyApp.S3Client.get_object_metadata("my-bucket", "large-file.zip")
      {:ok, %{content_length: 1234567, content_type: "application/zip", etag: "\"abcdef1234567890\""}}

  """
  def get_object_metadata(bucket_name, key) do
    AWS.S3.head_object(bucket_name, key)
    |> AWS.request()
    |> case do
      {:ok, %{headers: headers}} -> {:ok, format_metadata(headers)}
      error -> {:error, error}
    end
  end

  @doc """
  Copies an object from one location to another within S3.

  ## Parameters

    - source_bucket: String name of the source bucket
    - source_key: String path/name of the source file
    - destination_bucket: String name of the destination bucket
    - destination_key: String path/name for the destination file

  ## Examples

      iex> MyApp.S3Client.copy_object("source-bucket", "original.txt", "dest-bucket", "copy.txt")
      {:ok, %{copy_source_version_id: nil, etag: "\"abcdef1234567890\"", expiration: nil}}

  """
  def copy_object(source_bucket, source_key, destination_bucket, destination_key) do
    source = "#{source_bucket}/#{source_key}"

    AWS.S3.copy_object(destination_bucket, destination_key, source)
    |> AWS.request()
    |> case do
      {:ok, response} -> {:ok, response}
      error -> {:error, error}
    end
  end

  # Private helper functions

  defp build_headers(nil), do: []
  defp build_headers(content_type), do: [{"content-type", content_type}]

  defp build_presign_operation(:get, bucket, key) do
    AWS.S3.get_object(bucket, key)
  end

  defp build_presign_operation(:put, bucket, key) do
    AWS.S3.put_object(bucket, key, "")
  end

  defp format_metadata(headers) do
    headers
    |> Enum.map(fn {k, v} -> {String.downcase(k), v} end)
    |> Map.new()
  end
end
