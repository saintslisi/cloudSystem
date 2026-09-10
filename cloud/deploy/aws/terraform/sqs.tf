resource "aws_sqs_queue" "ai_dlq" {
    name = "${var.project_name}-ai-tasks-dlq"

    message_retention_seconds = 1209600
    tags = {
        Name = "${var.project_name}-ai-tasks-dlq"
    }
}

resource "aws_sqs_queue" "ai_queue" {
    name = "${var.project_name}-ai-task-queue"

    visibility_timeout_seconds = 300

    redrive_policy = jsonencode({
        deadLetterTargetArn = aws_sqs_queue.ai_dlq.arn
        maxReceiveCount = 3
    })
    tags = {
        Name = "${var.project_name}-ai-task-queue"
    }
}
