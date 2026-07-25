defmodule Mehungry.S3 do
  @moduledoc """
  A module for interacting with AWS S3.
  Provides functions for uploading, downloading, listing, and deleting objects in S3 buckets.
  """

  @doc """
  Uploads a file to an S3 bucket.

  ## Parameters
    - bucket: The name of the S3 bucket
    - key: The key (path) where the file will be stored in the bucket
    - file_path: The local path to the file to be uploaded
    - opts: Additional options for the upload (content-type, etc.)

  ## Returns
    - {:ok, response} on success
    - {:error, reason} on failure
  """
  def upload_file(bucket, key, file_path, opts \\ []) do
    file_path
    |> File.read!()
    |> upload_binary(bucket, key, opts)
  end

  @doc """
  Uploads binary data to an S3 bucket.

  ## Parameters
    - data: The binary data to upload
    - bucket: The name of the S3 bucket
    - key: The key (path) where the data will be stored in the bucket
    - opts: Additional options for the upload (content-type, etc.)

  ## Returns
    - {:ok, response} on success
    - {:error, reason} on failure
  """
  def upload_binary(data, bucket, key, opts \\ []) do
    ExAws.S3.put_object(bucket, key, data, opts)
    |> ExAws.request()
  end

  @doc """
  Downloads a file from an S3 bucket.

  ## Parameters
    - bucket: The name of the S3 bucket
    - key: The key (path) of the file in the bucket
    - destination_path: Optional local path where the file should be saved

  ## Returns
    - {:ok, body} or {:ok, :file_written} on success
    - {:error, reason} on failure
  """
  def download_file(bucket, key, destination_path \\ nil) do
    case ExAws.S3.get_object(bucket, key) |> ExAws.request() do
      {:ok, %{body: body}} = response ->
        case destination_path do
          nil ->
            response

          path ->
            File.write!(path, body)
            {:ok, :file_written}
        end

      error ->
        error
    end
  end

  @doc """
  Lists objects in an S3 bucket, following pagination so every key is returned
  (a single `list_objects` page caps at 1000 keys).

  ## Parameters
    - bucket: The name of the S3 bucket
    - prefix: Optional prefix to filter the objects by
    - opts: Additional options for listing

  ## Returns
    - {:ok, %{body: %{contents: [...]}}} on success — the aggregated contents
      across every page, in the same shape as a single-page response
    - {:error, reason} on failure
  """
  def list_objects(bucket, prefix \\ nil, opts \\ []) do
    opts = if prefix, do: Keyword.put(opts, :prefix, prefix), else: opts

    list_objects_paged(bucket, opts, nil, [])
  end

  # Walks the marker-based pagination, accumulating contents. On the last page
  # (is_truncated falsey) it returns the aggregated contents in a single-page
  # response shape so callers can keep reading `objects.body.contents`.
  defp list_objects_paged(bucket, opts, marker, acc) do
    opts = if marker, do: Keyword.put(opts, :marker, marker), else: opts

    case ExAws.S3.list_objects(bucket, opts) |> ExAws.request() do
      {:ok, %{body: %{contents: contents} = body} = response} ->
        acc = acc ++ contents

        if truncated?(body) and contents != [] do
          list_objects_paged(bucket, opts, List.last(contents).key, acc)
        else
          {:ok, put_in(response.body.contents, acc)}
        end

      {:error, _reason} = error ->
        error
    end
  end

  # ExAws surfaces is_truncated as the string "true"/"false" from the XML body.
  defp truncated?(%{is_truncated: t}), do: t in [true, "true"]
  defp truncated?(_), do: false

  @doc """
  Deletes an object from an S3 bucket.

  ## Parameters
    - bucket: The name of the S3 bucket
    - key: The key (path) of the object to delete

  ## Returns
    - {:ok, response} on success
    - {:error, reason} on failure
  """
  def delete_object(bucket, key, request_opts \\ []) do
    ExAws.S3.delete_object(bucket, key)
    |> ExAws.request(request_opts)
  end

  @doc """
  Generates a presigned URL for an S3 object.

  ## Parameters
    - bucket: The name of the S3 bucket
    - key: The key (path) of the object
    - expires_in: URL expiration time in seconds (default: 3600)
    - operation: The operation to perform (:get or :put) (default: :get)

  ## Returns
    - {:ok, url} on success
    - {:error, reason} on failure
  """
  def presigned_url(bucket, key, expires_in \\ 3600, operation \\ :get) do
    ExAws.S3.presigned_url(ExAws.Config.new(:s3), operation, bucket, key, expires_in: expires_in)
  end

  @doc """
  Checks if an object exists in an S3 bucket.

  ## Parameters
    - bucket: The name of the S3 bucket
    - key: The key (path) of the object to check

  ## Returns
    - true if the object exists
    - false if the object does not exist
  """
  def object_exists?(bucket, key) do
    case ExAws.S3.head_object(bucket, key) |> ExAws.request() do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Creates a bucket in S3.

  ## Parameters
    - bucket: The name of the bucket to create
    - region: The AWS region to create the bucket in
    - opts: Additional options for bucket creation

  ## Returns
    - {:ok, response} on success
    - {:error, reason} on failure
  """
  def create_bucket(bucket, region \\ "us-east-1", opts \\ []) do
    ExAws.S3.put_bucket(bucket, region, opts)
    |> ExAws.request()
  end

  @doc """
  Deletes a bucket from S3.

  ## Parameters
    - bucket: The name of the bucket to delete

  ## Returns
    - {:ok, response} on success
    - {:error, reason} on failure
  """
  def delete_bucket(bucket) do
    ExAws.S3.delete_bucket(bucket)
    |> ExAws.request()
  end
end
