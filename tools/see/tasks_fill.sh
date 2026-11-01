# Sourced by a scenario: a real task list in the sealed home, through the real
# `task`, with a long title, a long project, an overdue task, one running and
# some with neither date nor project.
cat > "$HOME/.taskrc" <<RC
data.location=$HOME/.task
confirmation=off
RC
add() { task rc.verbose=nothing add "$@" > /dev/null; }
add "Send the seminar notes" project:university priority:H due:today scheduled:today
add "Read the paper on distance fields" project:research.reading +reading due:tomorrow
add "A task with a title long enough to run well past the edge of any panel it is put in" project:a.project.name.that.is.far.too.long.for.its.row priority:M
add "Book the dentist" due:yesterday
add "Water the plants"
add "Renew the passport" due:eow scheduled:tomorrow
add "Sort the tax papers" project:home priority:L
task rc.verbose=nothing rc.confirmation=off 2 start > /dev/null
