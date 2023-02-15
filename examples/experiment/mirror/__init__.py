from otree.api import *
import os
import random
import string

DUCKSOUP_URL = os.getenv("OTREE_DUCKSOUP_URL", "http://localhost:8100/")
DUCKSOUP_JS_URL = DUCKSOUP_URL + "scripts/lib/ducksoup.js"

VIDEO_DURATION = 20 # seconds

def random_id():
    return ''.join(random.choice(string.ascii_lowercase) for i in range(16))

class Player(BasePlayer):
    name = models.StringField()

class Constants(BaseConstants):
    num_rounds = 1
    players_per_group = None
    name_in_url = 'mirror'

class Subsession(BaseSubsession):
    pass

class Group(BaseGroup):
    pass

class Introduction(Page):
    form_model = 'player'
    form_fields = ['name']

class DuckSoup(Page):
    timeout_seconds = VIDEO_DURATION + 2

    def live_method(player, data):
        kind = data['kind']
        if kind == 'end':
            return {player.id_in_group: 'next'}

    def vars_for_template(player):
        return dict(
            duckSoupJsUrl=DUCKSOUP_JS_URL
        )
            
    def js_vars(player):
        player_id = random_id()
        return dict(
            ducksoupURL=DUCKSOUP_URL,
            peerOptions=dict(
                roomId=player_id,
                userId=player_id,
                duration=VIDEO_DURATION,
                namespace="mirror-experiment",
                videoCodec="H264",
                size=1,
                audioFx="pitch pitch=0.8",
            )
        )

class End(Page):
    pass

page_sequence = [
    Introduction,
    DuckSoup,
    End
]
