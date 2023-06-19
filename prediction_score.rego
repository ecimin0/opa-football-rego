package opa_football.scoring.prediction

import future.keywords.if
import future.keywords.in
import future.keywords.every


# input is the representation of the user's prediction data

# data represents the information about each fixture needed to do the scoring


# helpers
# ---------------------------------------------------------
input_valid := true if {
    is_number(input.home_goals)
    is_number(input.away_goals)
	is_string(input.main_team)
	
	is_array(input.scorers)
    every scorer in input.scorers {
        is_object(scorer)
        is_boolean(scorer.fgs)
        is_number(scorer.num_goals)
        is_string(scorer.real_name)
    }
} else := false

data_valid := true if {
	is_number(data.fixture.goals_home)
    is_number(data.fixture.goals_away)
    is_boolean(data.fixture.teams.home.winner)
    is_boolean(data.fixture.teams.away.winner)
    is_string(data.fixture.home_name)
    is_string(data.fixture.away_name)
    
    is_array(data.fixture.events)
	every event in data.fixture.events {
		is_string(event.type)
		is_string(event.player.name)
        is_string(event.team.name)
        is_string(event.detail)
    }
} else := false

main_team_in_fixture := true if {
	input.main_team == lower(data.fixture.teams.home.name)
}

main_team_in_fixture := true if {
    input.main_team == lower(data.fixture.teams.away.name)
}

# these rules are identical to those in the Discord prediction bot's logic,
# but expressed via Rego instead
# ---------------------------------------------------------
# 2 points – correct result (W/D/L)
match_winner["home"] {
	data.fixture.teams.home.winner == true
}

match_winner["away"] {
	data.fixture.teams.away.winner == true
}

match_winner["draw"] {
	data.fixture.teams.home.winner == false
	data.fixture.teams.away.winner == false
}

predict_winner["home"] {
	input.home_goals > input.away_goals
}

predict_winner["away"] {
	data.fixture.goals_away > data.fixture.goals_home
}

predict_winner["draw"] {
	data.fixture.goals_home == data.fixture.goals_away
}

correct_result := 2 if {
	predict_winner == match_winner
} else := 0 {
	true
}
# ---------------------------------------------------------

# 2 points – correct number of main team goals
main_team_home if {
	data.fixture.home_name == input.main_team
}

main_team_away if {
	data.fixture.away_name == input.main_team
}

correct_main_team_goals_home := 2 if {
	main_team_home
	input.home_goals == data.fixture.goals_home
} else := 0 {
	true
}

correct_main_team_goals_away := 2 if {
	main_team_away
	input.away_goals == data.fixture.goals_away
} else := 0 {
	true
}

# ---------------------------------------------------------

# 1 point – correct number of goals conceded
correct_goals_against_home := 1 if {
	main_team_home
	input.away_goals == data.fixture.goals_away
} else := 0 {
	true
}

correct_goals_against_away := 1 if {
	main_team_away
	input.home_goals == data.fixture.goals_home
} else := 0 {
	true
}

# ---------------------------------------------------------

# 2 points bonus – all scorers correct
# 1 point – each correct scorer
# to do: make sure this works if they predict no scorers
expand(player) := x if {
	n := numbers.range(1, player.num_goals)
	x := [p |
		n[_]
		p := player.real_name
	]
}

expanded_predict_scorers := [final |
	final_t := input.scorers[_]
	final := expand(final_t)[_]
]

scorers_union := predict_scorers_set & match_scorers_set

getCountPlayer(name, listCheck) := x {
    x := count([x | 
		name == listCheck[x]
    ])
}

playerPoints(name, predict, actual) := x {
	x := min([getCountPlayer(name, predict), getCountPlayer(name, actual)])
}
    
final_scorers_correct := [x |
	pn := scorers_union[_]
    x := playerPoints(pn, expanded_predict_scorers, match_scorers)
]

correct_final_score_for_scorers := sum(final_scorers_correct)

final_scorers_correct_names := [x |
	some x in predict_scorers
	x in scorers_union
]

predict_scorers := [k.real_name | k := input.scorers[_]]

predict_scorers_set := {k | k := predict_scorers[_]}

match_scorers := [k.player.name |
	k := data.fixture.events[_]
	k.type == "Goal"
	lower(k.team.name) == input.main_team
]

match_scorers_set := {k | k := match_scorers[_]}

correct_all_scorers := 2 if {
	sort(expanded_predict_scorers) == sort(match_scorers)
} else := 0 {
	true
}

# ---------------------------------------------------------

# No points for scorers if your prediction's goals exceed the actual goals by 4+ \
# No points for any part of the prediction related to scorers or fgs if predicted goals > actual goals + 4
no_points_too_many_goals_home if {
	main_team_home
	input.home_goals - data.fixture.goals_home >= 4
}

no_points_too_many_goals_away if {
	main_team_away
	input.away_goals - data.fixture.goals_away >= 4
}

# ---------------------------------------------------------

# 1 point – correct FGS (first goal scorer, only main team)
predict_fgs := [k.real_name |
	k := input.scorers[_]
	k.fgs == true
]

correct_fgs := 1 if {
	predict_fgs[0] == match_scorers[0]
} else := 0 {
	true
}

# ---------------------------------------------------------

# calculate final score; final calculation may not include undefined rules/rule values
subtotal_score := ((((((correct_all_scorers + correct_main_team_goals_away) + correct_main_team_goals_home) + correct_fgs) + correct_goals_against_away) + correct_goals_against_home) + correct_final_score_for_scorers) + correct_result if {
	not no_points_too_many_goals_home
	not no_points_too_many_goals_away
} else := (((correct_main_team_goals_away + correct_main_team_goals_home) + correct_goals_against_away) + correct_goals_against_home) + correct_result {
	true
}

invalid[msg] {
	not input_valid
    msg := "failure: input validation failure"
}
invalid[msg] {
	not data_valid
    msg := "failure: data validation failure"
}
invalid[msg] {
	not main_team_in_fixture
    msg := "failure: main team not found in fixture"
}

total_score := subtotal_score if {
    count(invalid) == 0 # since invalid always 'exists' must check if empty
} else := msg {
	msg := concat(", ", invalid)
}

# ---------------------------------------------------------
