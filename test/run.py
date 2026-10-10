"""Headless checks of AI Crew on vanilla: python test/run.py [CASE [TICKS]] | --all [-j N]"""
from factorio_paths import main

main(__file__, {"ac-test": 36010, "ac-place": 36010, "ac-asmfurnace": 36010, "ac-upgrade": 18010, "ac-arm": 18010,
                "ac-arm2": 36010, "ac-human": 8900, "ac-defend": 9100, "ac-spam": 7300, "ac-car": 12100,
                "ac-train": 9100, "ac-belt": 6100, "ac-hint": 18800, "ac-jet": 6100, "ac-roam": 36010, "ac-farpower": 18100,
                "ac-fight": 36010, "ac-line": 72010, "ac-power": 144010, "ac-boot": 36010, "ac-goal": 36010,
                "ac-path": 7510})
