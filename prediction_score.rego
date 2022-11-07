package opa_football.scoring

import future.keywords.if
import future.keywords.in

# these rules are implemented in python alongside the rest of the bot logic, but
# why not do a POC in OPA/Rego?

# no offense meant in particular to Leicester FC, this just happened to be the 
# match I grabbed from the API to experiment with

# Rules
# ---------------------------------------------------------

# 2 points – correct result (W/D/L)
match_winner["home"] {
	# 	data.goals_home > data.goals_away
	data.teams.home.winner == true
}

match_winner["away"] {
	# 	data.goals_away > data.goals_home
	data.teams.away.winner == true
}

match_winner["draw"] {
	#     data.goals_home == data.goals_away
	data.teams.home.winner == false
	data.teams.away.winner == false
}

predict_winner["home"] {
	input.home_goals > input.away_goals
}

predict_winner["away"] {
	data.goals_away > data.goals_home
}

predict_winner["draw"] {
	data.goals_home == data.goals_away
}

# correct_result[correct_result_score] {
# 	predict_winner == match_winner
# 	correct_result_score = 2
# }

correct_result := 2 if {
	predict_winner == match_winner
} else := 0 if {
	true
}

# ---------------------------------------------------------

# 2 points – correct number of Arsenal goals
# the bot's main club is Arsenal, sorry not sorry :D

arsenal_home if {
	data.home_name == "arsenal"
}

arsenal_away if {
	data.away_name == "arsenal"
}

correct_arsenal_goals_home := 2 if {
	arsenal_home
	input.home_goals == data.goals_home
} else := 0 if {
	true
}

correct_arsenal_goals_away := 2 if {
	arsenal_away
	input.away_goals == data.goals_away
} else := 0 if {
	true
}

# ---------------------------------------------------------

# 1 point – correct number of goals conceded
correct_goals_against_home := 1 if {
	arsenal_home
	input.away_goals == data.goals.away
} else := 0 if {
	true
}

correct_goals_against_away := 1 if {
	arsenal_away
	input.home_goals == data.goals.home
} else := 0 if {
	true
}

# ---------------------------------------------------------

# 2 points bonus – all scorers correct
# 1 point – each correct scorer
# to do: make sure this works if they predict no scorers
magic(player) := x if {
	n := numbers.range(1, player.num_goals)
	x := [p |
		n[_]
		p := player.real_name
	]
}

expanded_predict_scorers := [final |
	final_t := input.scorers[_]
	final := magic(final_t)[_]
]

scorers_union := predict_scorers_set & match_scorers_set

getCountPlayer(name, listCheck) := x if {
	x := count([x |
		name == listCheck[x]
	])
}

playerPoints(name, predict, actual) := x if {
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
	k := data.events[_]
	k.type == "Goal"
	k.team.name == "Arsenal"
]

match_scorers_set := {k | k := match_scorers[_]}

correct_all_scorers := 2 if {
	sort(expanded_predict_scorers) == sort(match_scorers)
} else := 0 if {
	true
}

# ---------------------------------------------------------

# No points for scorers if your prediction's goals exceed the actual goals by 4+ \
# No points for any part of the prediction related to scorers or fgs if predicted goals > actual goals + 4
no_points_too_many_goals_home if {
	arsenal_home
	input.home_goals - data.goals.home >= 4
}

no_points_too_many_goals_away if {
	arsenal_away
	input.away_goals - data.goals.away >= 4
}

# ---------------------------------------------------------

# 1 point – correct FGS (first goal scorer, only Arsenal)
predict_fgs := [k.real_name |
	k := input.scorers[_]
	k.fgs == true
]

correct_fgs := 1 if {
	predict_fgs[0] == match_scorers[0]
} else := 0 if {
	true
}

# ---------------------------------------------------------

# calculate final score; final calculation may not include undefined rules/rule values
final_prediction_score := ((((((correct_all_scorers + correct_arsenal_goals_away) + correct_arsenal_goals_home) + correct_fgs) + correct_goals_against_away) + correct_goals_against_home) + correct_final_score_for_scorers) + correct_result if {
	not no_points_too_many_goals_home
	not no_points_too_many_goals_away
} else := (((correct_arsenal_goals_away + correct_arsenal_goals_home) + correct_goals_against_away) + correct_goals_against_home) + correct_result if {
	true
}

# ---------------------------------------------------------
