output "splunk_public_ip" {
  value       = aws_instance.splunk.public_ip
  description = "Splunk server public IP"
}

output "splunk_url" {
  value       = "http://${aws_instance.splunk.public_ip}:8000"
  description = "Splunk Web UI URL"
}

output "s3_artifacts_bucket" {
  value       = aws_s3_bucket.artifacts.id
  description = "Shared S3 artifacts bucket"
}

output "team_access_keys" {
  value = {
    for k, v in aws_iam_access_key.team :
    k => {
      access_key_id     = v.id
      secret_access_key = v.secret
    }
  }
  sensitive   = true
  description = "Team member AWS credentials"
}