defmodule Mehungry.S3Manager do
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
      error -> error
    end
  end

  @doc """
  Lists objects in an S3 bucket.

  ## Parameters
    - bucket: The name of the S3 bucket
    - prefix: Optional prefix to filter the objects by
    - opts: Additional options for listing

  ## Returns
    - {:ok, objects} on success
    - {:error, reason} on failure
  """
  def list_objects(bucket, prefix \\ nil, opts \\ []) do
    opts = if prefix, do: Keyword.put(opts, :prefix, prefix), else: opts

    ExAws.S3.list_objects(bucket, opts)
    |> IO.inspect()
    |> ExAws.request()
  end

  @doc """
  Deletes an object from an S3 bucket.

  ## Parameters
    - bucket: The name of the S3 bucket
    - key: The key (path) of the object to delete

  ## Returns
    - {:ok, response} on success
    - {:error, reason} on failure
  """
  def delete_object(bucket, key) do
    ExAws.S3.delete_object(bucket, key)
    |> ExAws.request()
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
    {:ok, ExAws.S3.presigned_url(ExAws.Config.new(:s3), operation, bucket, key, expires_in: expires_in)}
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
