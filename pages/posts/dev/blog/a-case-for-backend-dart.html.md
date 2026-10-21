---
title: A case for backend Dart
description: Real-world server-side Dart on AWS Lambda with relic, and what it looks like in production.
date: 2026-10-18
---

Hi all,

Wanted to share my experience with real-world server-side Dart.

A long-time Flutter + Python dev, and a linguist in a previous life, I always enjoyed the expressivity of Dart. But in my career, I live in AWS, there is no official AWS SDK in Dart, so I couldn’t write my server apps in Dart.

How sad. So clearly, had to build my own.

There is this fitness app I built for myself (yeah, I know) that was a natural Flutter choice from the start, had a bit of a twisted history on the backend. Initially I wrote the server in Go and wrapped it in an AWS Lambda function. The more I wrote Go, the less I enjoyed it.

Finally, I started researching Dart solutions. Tried a bunch, the one with the frog, obviously Shelf, Serverpod felt heavy and opinionated. And then I saw Relic and frankly, just enjoyed the Dart that it was written in. Relic is to Serverpod feels like what Starlette is to FastAPI, and I wrote a lot of Starlette in my days.

So, had to try.

Eventually, all my handler signatures stabilized in this shape

```dart
typedef ModelHandler = Future<Model?> Function(Request);
```

where `Model` is an interface for my JSON responses and `Request` is a Relic’s primitive. This gives me FastAPI-style typed inputs and outputs. Sure, input parsing and validation is a bit of manual work, but oh well.

As far as the AWS SDK, it ended up a boto3-shaped wrapper that signs every request to AWS API with SigV4. Really, nothing fancy.

So, high-level arch:

API Gateway → AWS Lambda + Lambda Web Adapter + Dart’s Relic server app → Postgres on Supabase.

The API app sends SQS events for background jobs, those requests are signed with the same AWS library.

Gaps I felt: no Swagger and no easy way to get there. My app has a Developer API and an MCP and I feel that absence deeply.

Some numbers from my serverless “production”:

- Dart performs better than Go in my specific case: a faster and more efficient compiler, my entire app is 5.2 MB (two, actually: API and MCP) and serverless cold starts are great.
- warm lambdas - p50 15 ms, p95 103 ms, p99 590 ms
- cold Lambda inits - p50 119 ms, p95 166 ms, min 86 ms
- memory: ~48 MB avg, 81 MB max of 512 MB provisioned in my Lambda.

All of that on a free Supabase instance.

Too early to celebrate, of course, but as far as compute goes, Dart surprises pleasantly, and I now get to write my apps in it.
