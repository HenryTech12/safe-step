import asyncio
from types import SimpleNamespace as NS

from safestep_agent.languages import get_language
from safestep_agent.scene import SceneDescriber


class FakeModels:
    def __init__(self, text="An open gutter is ahead on your left. Shoprite is on your right."):
        self.text = text
        self.calls = []

    async def generate_content(self, *, model, contents, config):
        self.calls.append((model, contents))
        return NS(text=self.text)


def fake_client(models):
    return NS(aio=NS(models=models))


async def test_requests_one_frame_and_captions_it():
    models = FakeModels()
    sent = []
    scene = None

    async def request(rid):
        sent.append(rid)
        asyncio.get_running_loop().call_soon(scene.on_frame, rid, b"\xff\xd8jpeg")

    scene = SceneDescriber(request, get_language("pcm"), client=fake_client(models), model="m")
    out = await scene.describe()
    assert out.startswith("SCENE") and "open gutter" in out
    assert len(sent) == 1
    model, contents = models.calls[0]
    assert model == "m" and "Nigerian Pidgin" in contents[1]


async def test_frame_timeout(monkeypatch):
    import safestep_agent.scene as sc

    monkeypatch.setattr(sc, "FRAME_TIMEOUT_S", 0.05)

    async def request(rid):
        return None

    scene = SceneDescriber(request, get_language("en"), client=fake_client(FakeModels()))
    assert (await scene.describe()).startswith("NO_FRAME")


async def test_unknown_frame_ids_are_ignored():
    scene = SceneDescriber(lambda rid: None, get_language("en"), client=fake_client(FakeModels()))
    scene.on_frame("nobody-asked", b"x")  # must not raise
