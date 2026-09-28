#!/usr/bin/env python3
"""plant-assistant: the assistant answers by calling the plant's tools, and every answer shows the calls behind it; an answer with no call says so."""
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "tools"))
from appplayer import AppPlayer  # noqa: E402
from mcpclient import Server  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
CAP = os.path.join(HERE, "captures")

ASSISTANT = os.path.join(HERE, "assistant")
with Server(["dart", "run", "bin/server.dart"], cwd=ASSISTANT) as s:
    reading = s.call("assistant.ask", {"question": "how is CONV-03 doing?"})
    assert reading["grounded"], "a question about a machine must reach the plant"
    weather = s.call("assistant.ask", {"question": "what is the weather like?"})
    assert not weather["grounded"] and weather["notice"], weather

ap = AppPlayer()
ap.register_server("com.makemind.sample.plant_assistant", "Plant assistant", cwd=ASSISTANT)
ap.restart()
ap.open_server("com.makemind.sample.plant_assistant")
ap.wait_text("TOOL CALLS")
ap.shot(f"{CAP}/01_idle.png")
ap.tap("How is CONV-03 doing?")
ap.wait_text("equipment.read")
ap.shot(f"{CAP}/02_reading_grounded.png")
ap.tap("Checklist before CONV-03")
ap.wait_text("checklist.get")
ap.shot(f"{CAP}/03_checklist_grounded.png")
ap.tap("What is the weather like?")
ap.wait_text("no tool call")
ap.shot(f"{CAP}/04_ungrounded_warned.png")
print("plant-assistant: two grounded answers with their calls on screen, one ungrounded answer flagged")
