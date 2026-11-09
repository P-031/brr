#!/bin/sh
# Replaces the image's init script. Prisma migrations create the postgis extension,
# so the database must start without it or `prisma migrate` reports drift.
