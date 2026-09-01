#!/usr/bin/env python3
"""Convenience wrapper for enemy-sheet preprocessing."""

from prepare_character_sprites import prepare_enemies, validate_outputs


if __name__ == "__main__":
    prepared = prepare_enemies()
    print("prepared enemies: " + ", ".join(f"{k}={len(v)}" for k, v in prepared.items()))
    problems = validate_outputs()
    if problems:
        raise SystemExit("\n".join(problems))
