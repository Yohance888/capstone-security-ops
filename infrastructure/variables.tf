variable "aws_region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for tagging"
  default     = "capstone-security-ops"
}

variable "team_members" {
  description = "Team member usernames"
  type        = map(string)
  default = {
    cloud_architect = "yohance-cloud"
    soc_analyst     = "asante-soc"
    threat_intel    = "leo-threat"
    pen_tester      = "court-pen"
  }
}