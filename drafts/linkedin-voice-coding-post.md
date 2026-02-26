# LinkedIn Post Draft — Voice-First Coding Session

## Draft 1

Last night I coded an entire feature set using only my voice.

Not dictating to a text editor. Not using voice-to-text in a chat window. I was in a Discord voice channel, talking to my AI assistant, and it was writing code, running tests, opening PRs, and deploying — all from spoken instructions.

Here's what made it interesting: I was building the very tool I was using to talk to it.

The session started with a simple question: "Can you find a text-to-speech model that's more friendly for reading out pull requests?" Stuff like `1s` being read as "one s" instead of "one second." Markdown formatting being spoken as literal asterisks. Snake_case identifiers coming out as garbled nonsense.

My AI (Bel) researched the options, concluded it was a text preprocessing problem not a model problem, and proposed building a normalizer. I said "yeah, build it" — and a sub-agent spun up and wrote the module while we kept talking about other things.

Then I said "use my own messages from this channel as test cases." It pulled my recent Discord messages — full of markdown, code references, PR numbers — and used them as real-world integration tests. 83 tests, all passing.

That was the easy part.

The fun started when we tried to actually hear the results. The text-to-speech wasn't playing back. We discovered the barge-in system (which stops Bel from talking over you) was triggering on background noise — farm sounds, keyboard clicks, my daughter in the next room. Every little noise killed the audio response.

So we built a two-tier system: noise pauses the response, but only confirmed speech cancels it. If the noise stops within 500ms, playback resumes. That took about ten minutes of back-and-forth to design and implement — all via voice.

Then Whisper (the speech-to-text model) started hallucinating. It was prepending dozens of phantom "Thank you"s before my actual speech. The transcript would look like: "Thank you. Thank you. Thank you. Thank you. OK, read me the last PR." We built a prefix stripper that catches those hallucination patterns and preserves the real content.

At one point, I thought I'd lost the whole system. The gateway went down, the voice bot couldn't reconnect, and I spent about an hour debugging config files and restarting services from my phone — also via voice and text. There was a genuine moment where I wasn't sure I'd get it back up. But we got there.

The whole experience was pure dogfooding. I was building a voice interface while using that voice interface. Bugs surfaced naturally because I was hitting them in real time. "The audio cut out" → investigate → fix → "try again" → "still not working" → dig deeper → find the real root cause → fix → ship.

By the end of the night, we'd shipped:
- A TTS text normalizer (makes code-speak sound natural)
- Sentence-aware chunking (long responses split at natural boundaries)
- Whisper hallucination stripping
- Two-tier barge-in (pause on noise, cancel on speech)
- A fix for the voice bridge that lets my AI's responses be read aloud seamlessly

125 tests. All merged. All running in production by the end of the session.

I've been building software for 15 years and I've never coded like this before. No keyboard. No screen for most of it. Just talking — describing what I wanted, hearing the results, iterating in real time. It's not perfect yet (Whisper still hallucinates, the barge-in needs tuning) but the loop is tight enough to be genuinely productive.

The future of development isn't typing faster. It's describing better.

#AI #VoiceCoding #DeveloperExperience #Dogfooding #BuildInPublic
