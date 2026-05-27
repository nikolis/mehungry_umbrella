defmodule Mehungry.S3Client do
  @moduledoc """
  A module for interacting with AWS S3 using ExAws.
  Provides functions for common S3 operations like listing buckets,
  uploading, downloading, and deleting objects.
  """

  @doc """
  Lists all buckets in your AWS account.
  """
  def list_buckets do
    ExAws.S3.list_buckets()
    |> ExAws.request()
    |> case do
      {:ok, %{body: %{buckets: buckets}}} -> {:ok, buckets}
      error -> {:error, error}
    end
  end

  @doc """
  Creates a new bucket in S3.
  """
  def create_bucket(bucket_name) do
    ExAws.S3.put_bucket(bucket_name, "eu-central-1")
    |> ExAws.request()
    |> case do
      {:ok, response} -> {:ok, response}
      error -> {:error, error}
    end
  end

  @doc """
  Lists objects in a bucket.
  """
  def list_objects(bucket_name, prefix \\ nil) do
    opts = if prefix, do: [prefix: prefix], else: []

    ExAws.S3.list_objects(bucket_name, opts)
    |> ExAws.request()
    |> case do
      {:ok, %{body: %{contents: contents}}} -> {:ok, contents}
      error -> {:error, error}
    end
  end

  @doc """
  Uploads a file to S3 from a local path.
  """
  def upload_file(bucket_name, key, file_path, content_type \\ nil) do
    with {:ok, file_binary} <- File.read(file_path) do
      opts = if content_type, do: [content_type: content_type], else: []

      ExAws.S3.put_object(bucket_name, key, file_binary, opts)
      |> ExAws.request()
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
  """
  def upload_binary(bucket_name, key, data, content_type \\ nil) do
    opts = if content_type, do: [content_type: content_type], else: []

    ExAws.S3.put_object(bucket_name, key, data, opts)
    |> ExAws.request()
    |> case do
      {:ok, response} -> {:ok, response}
      error -> {:error, error}
    end
  end

  @doc """
  Downloads a file from S3.
  """
  def download_file(bucket_name, key) do
    ExAws.S3.get_object(bucket_name, key)
    |> ExAws.request()
    |> case do
      {:ok, response} -> {:ok, response}
      error -> {:error, error}
    end
  end

  @doc """
  Downloads a file from S3 and saves it to a local path.
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
  """
  def delete_object(bucket_name, key) do
    ExAws.S3.delete_object(bucket_name, key)
    |> ExAws.request()
    |> case do
      {:ok, response} -> {:ok, response}
      error -> {:error, error}
    end
  end

  @doc """
  Generates a pre-signed URL for temporary access to an S3 object.
  """
  def generate_presigned_url(bucket_name, key, expires_in \\ 3600, method \\ :get) do
    config = ExAws.Config.new(:s3)

    ExAws.S3.presigned_url(config, method, bucket_name, key, expires_in: expires_in)
    |> case do
      {:ok, url} -> {:ok, url}
      error -> {:error, error}
    end
  end

  @doc """
  Gets the metadata for an S3 object without downloading its content.
  """
  def get_object_metadata(bucket_name, key) do
    ExAws.S3.head_object(bucket_name, key)
    |> ExAws.request()
    |> case do
      {:ok, %{headers: headers}} -> {:ok, format_metadata(headers)}
      error -> {:error, error}
    end
  end

  @doc """
  Copies an object from one location to another within S3.
  """
  def copy_object(source_bucket, source_key, destination_bucket, destination_key) do
    source = "#{source_bucket}/#{source_key}"

    ExAws.S3.put_object_copy(destination_bucket, destination_key, source)
    |> ExAws.request()
    |> case do
      {:ok, response} -> {:ok, response}
      error -> {:error, error}
    end
  end

  defp format_metadata(headers) do
    headers
    |> Enum.map(fn {k, v} -> {String.downcase(k), v} end)
    |> Map.new()
  end
end
