"""On-clause generation, where we collect all unsolved (latent state dependent) on-clauses at the end"""
function generate_on_clauses(matrix, unformatted_matrix, object_decomposition, user_events, global_event_vector_dict, redundant_events_set, grid_size=16, desired_solution_count=1, desired_per_matrix_solution_count=1) 
  matrix, unformatted_matrix, object_decomposition, user_events, global_event_vector_dict, redundant_events_set, grid_size=16, desired_solution_count=1, desired_per_matrix_solution_count=1)
  object_types, object_mapping, background, dim = object_decomposition
  solutions = []

  # pre_filtered_matrix = pre_filter_with_direction_biases(matrix, user_events, object_decomposition) 
  # filtered_matrix = filter_update_function_matrix_multiple(pre_filtered_matrix, object_decomposition)[1]
  
  filtered_matrices = []

  # add non-random filtered matrices to filtered_matrices
  non_random_matrix = deepcopy(matrix)
  for row in 1:size(non_random_matrix)[1]
    for col in 1:size(non_random_matrix)[2]
      non_random_matrix[row, col] = filter(x -> !occursin("randomPositions", x), non_random_matrix[row, col])
    end
  end
  filtered_non_random_matrices = filter_update_function_matrix_multiple(non_random_matrix, object_decomposition, multiple=true)
  # filtered_non_random_matrices = filtered_non_random_matrices[1:min(4, length(filtered_non_random_matrices))]
  push!(filtered_matrices, filtered_non_random_matrices...)
  

  # add direction-bias-filtered matrix to filtered_matrices 
  pre_filtered_matrix = pre_filter_with_direction_biases(deepcopy(matrix), user_events, object_decomposition) 
  push!(filtered_matrices, filter_update_function_matrix_multiple(pre_filtered_matrix, object_decomposition, multiple=false)...)

  # add random filtered matrices to filtered_matrices 
  random_matrix = deepcopy(matrix)
  for row in 1:size(random_matrix)[1]
    for col in 1:size(random_matrix)[2]
      if filter(x -> occursin("uniformChoice", x) || occursin("randomPositions", x), random_matrix[row, col]) != []
        random_matrix[row, col] = filter(x -> occursin("uniformChoice", x) || occursin("randomPositions", x), random_matrix[row, col])
      end
    end
  end
  filtered_random_matrices = filter_update_function_matrix_multiple(random_matrix, object_decomposition, multiple=true)
  filtered_random_matrices = filtered_random_matrices[1:min(4, length(filtered_random_matrices))]
  push!(filtered_matrices, filtered_random_matrices...)

  # add "chaos" solution to filtered_matrices 
  filtered_unformatted_matrix = filter_update_function_matrix_multiple(unformatted_matrix, object_decomposition, multiple=false)[1]
  push!(filtered_matrices, filter_update_function_matrix_multiple(construct_chaos_matrix(filtered_unformatted_matrix, object_decomposition), object_decomposition, multiple=false)...)

  for filtered_matrix_index in 1:length(filtered_matrices)
    # @show filtered_matrix_index
    # @show length(filtered_matrices)
    # @show solutions
    filtered_matrix = filtered_matrices[filtered_matrix_index]

    if (length(filter(x -> x[1] != [], solutions)) >= desired_solution_count) # || ((length(filter(x -> x[1] != [], solutions)) > 0) && length(filter(x -> occursin("randomPositions", x), vcat(vcat(filtered_matrix...)...))) > 0) 
      # if we have reached a sufficient solution count or have found a solution before trying random solutions, exit
      println("BREAKING")
      # @show length(solutions)
      break
    end

    # initialize variables
    on_clauses = []
    global_var_dict = Dict()    
    global_state_update_times_dict = Dict(1 => ["" for x in 1:length(user_events)])
    object_specific_state_update_times_dict = Dict()
  
    global_state_update_on_clauses = []
    object_specific_state_update_on_clauses = []
    state_update_on_clauses = []

    # construct anonymized_filtered_matrix
    anonymized_filtered_matrix = deepcopy(filtered_matrix)
    for i in 1:size(matrix)[1]
      for j in 1:size(matrix)[2]
        anonymized_filtered_matrix[i,j] = [replace(filtered_matrix[i, j][1], "id) $(i)" => "id) x")]
      end
    end

    # construct dictionary mapping type id to unsolved update functions (at initialization, all update functions)
    update_functions_dict = Dict()
    type_ids = sort(map(t -> t.id, object_types))
    for type_id in type_ids 
      object_ids_with_type = filter(k -> filter(obj -> !isnothing(obj), object_mapping[k])[1].type.id == type_id, collect(keys(object_mapping)))
      if object_ids_with_type != [] 
        update_functions_dict[type_id] = unique(filter(r -> r != "", vcat(map(id -> vcat(anonymized_filtered_matrix[id, :]...), object_ids_with_type)...)))
      end
    end

    new_on_clauses, state_based_update_functions_dict, event_vectors_dict, addObj_params_dict = generate_stateless_on_clauses(update_functions_dict, matrix, filtered_matrix, anonymized_filtered_matrix, global_object_decomposition, user_events, state_update_on_clauses, global_var_dict, global_event_vector_dict, redundant_events_set)
    push!(on_clauses, new_on_clauses...)
 
    # check if all update functions were solved; if not, proceed with state generation procedure
    if length(collect(keys(state_based_update_functions_dict))) == 0 
      push!(solutions, ([deepcopy(on_clauses)..., deepcopy(state_update_on_clauses)...], deepcopy(global_object_decomposition), deepcopy(global_var_dict)))
    else # GENERATE NEW STATE 
      type_ids = collect(keys(state_based_update_functions_dict))

      # compute co-occurring event for each state-based update function 
      co_occurring_events_dict = Dict() # keys are co-occurring events, values are lists of tuples (type_id, update_function) where update_function has that co-occurring event
      events = collect(keys(event_vector_dict))
      for type_id in type_ids 
        for update_function in state_based_update_functions_dict[type_id]
          # compute co-occurring event 
          object_ids_with_type = filter(k -> filter(obj -> !isnothing(obj), object_mapping[k])[1].type.id == type_id, collect(keys(object_mapping)))
          update_function_times_dict = Dict(map(obj_id -> obj_id => findall(r -> r == update_function, anonymized_filtered_matrix[obj_id, :]), object_ids_with_type))
          co_occurring_events = []
          for event in events
            if event_vector_dict[event] isa AbstractArray
              event_vector = event_vector_dict[event]
              co_occurring = foldl(&, map(update_function_times -> is_co_occurring(event, event_vector, update_function_times), collect(values(update_function_times_dict))), init=true)      
            
              if co_occurring
                false_positive_count = foldl(+, map(k -> num_false_positives(event_vector, update_function_times_dict[k], object_mapping[k]), collect(keys(update_function_times_dict))), init=0)
                push!(co_occurring_events, (event, false_positive_count))
              end
            elseif (Set(collect(keys(event_vector_dict[event]))) == Set(collect(keys(update_function_times_dict))))
              event_vector = event_vector_dict[event]
              co_occurring = foldl(&, map(id -> is_co_occurring(event, event_vector[id], update_function_times_dict[id]), collect(keys(update_function_times_dict))), init=true)
              
              if co_occurring
                false_positive_count = foldl(+, map(id -> num_false_positives(event_vector[id], update_function_times_dict[id], object_mapping[id]), collect(keys(update_function_times_dict))), init=0)
                push!(co_occurring_events, (event, false_positive_count))
              end
            end
          end
          co_occurring_events = sort(filter(x -> !occursin("|", x[1]), co_occurring_events), by=x -> x[2]) # [1][1]
          if filter(x -> !occursin("globalVar", x[1]), co_occurring_events) != []
            co_occurring_events = filter(x -> !occursin("globalVar", x[1]), co_occurring_events)
          end
          best_co_occurring_events = sort(filter(e -> e[2] == minimum(map(x -> x[2], co_occurring_events)), co_occurring_events), by=z -> length(z[1]))
          # # @show best_co_occurring_events
          co_occurring_event = best_co_occurring_events[1][1]        

          if (type_id, co_occurring_event) in keys(co_occurring_events_dict)
            push!(co_occurring_events_dict[(type_id, co_occurring_event)], update_function)
          else
            co_occurring_events_dict[(type_id, co_occurring_event)] = [update_function]
          end
        end
      end

      # initialize problem contexts 
      problem_contexts = []
      solutions_per_matrix_count = 0 

      problem_context = (co_occurring_events_dict, 
                         on_clauses,
                         global_var_dict,
                         global_object_decomposition, 
                         global_state_update_times_dict,
                         object_specific_state_update_times_dict,
                         global_state_update_on_clauses,
                         object_specific_state_update_on_clauses,
                         state_update_on_clauses)

      push!(problem_contexts, problem_context)
      first_context = true
      failed = false
      while problem_contexts != [] && solutions_per_matrix_count < desired_per_matrix_solution_count
        co_occurring_events_dict, 
        on_clauses,
        global_var_dict,
        global_object_decomposition, 
        global_state_update_times_dict,
        object_specific_state_update_times_dict,
        global_state_update_on_clauses,
        object_specific_state_update_on_clauses,
        state_update_on_clauses = problem_contexts[1]

        problem_contexts = problem_contexts[2:end]

        if first_context 
          first_context = false
        else
          # check if some update functions are actually solved by previously generated new state 
          new_on_clauses, state_based_update_functions_dict, _, _ = generate_stateless_on_clauses(update_functions_dict, matrix, filtered_matrix, anonymized_filtered_matrix, global_object_decomposition, user_events, state_update_on_clauses, global_var_dict, global_event_vector_dict, redundant_events_set)
          if new_on_clauses != [] 
            push!(on_clauses, new_on_clauses)
            co_occurring_events_dict = update_co_occurring_events_dict(co_occurring_events_dict, state_based_update_functions_dict)
          end
        end
        
        # generate new state until all unmatched update functions are matched 
        while length(collect(keys(co_occurring_events_dict))) != 0
          type_id, co_occurring_event = sort(collect(keys(co_occurring_events_dict)))[1]
          object_type = filter(t -> t.id == type_id, object_types)
          
          update_functions = co_occurring_events_dict[(type_id, co_occurring_event)]
          delete!(co_occurring_events_dict, (type_id, co_occurring_event))

          # construct update_function_times_dict for this type_id/co_occurring_event pair 
          times_dict = Dict() 
          object_ids_with_type = filter(k -> filter(obj -> !isnothing(obj), object_mapping[k])[1].type.id == type_id, collect(keys(object_mapping)))
          for update_function in update_functions 
            times_dict[update_function] = Dict(map(id -> id => findall(r -> r == update_function, vcat(anonymized_filtered_matrix[id, :]...)), object_ids_with_type))
            for object_id in object_ids_with_type 
              if times_dict[update_function][object_id] == []
                delete!(times_dict[update_function], object_id)
              end
            end
          end

          # determine if state is global or object-specific 
          state_is_global = foldl(&, map(u -> occursin("addObj", u), update_functions), init=true) 
          if foldl(&, map(u -> occursin("addObj", u), update_functions), init=true) || length(object_ids_with_type) == 1
            state_is_global = true
          else
            for update_function in update_functions 
              for time in 1:length(user_events)
                observation_values = map(id -> event_vectors_dict[update_function][id][time], object_ids_with_type)
                if (0 in observation_values) && (1 in observation_values)
                  state_is_global = false
                  break
                end
              end
              if !state_is_global
                break
              end
            end
          end

          if state_is_global 
            # construct new global state 
            state_solutions = generate_new_state_GLOBAL()
            if length(filter(sol -> sol[1] != "", state_solutions)) == 0 # failure 
              failed = true 
              println("STATE SEARCH FAILURE")
              break 
            else
              state_solutions = filter(sol -> sol[1] != "", state_solutions) 

              # old values 
              old_on_clauses = deepcopy(on_clauses)
              old_global_object_decomposition = deepcopy(global_object_decomposition)
              old_global_state_update_times_dict = deepcopy(global_state_update_times_dict)
              old_object_specific_state_update_times_dict = deepcopy(object_specific_state_update_times_dict)
              old_global_state_update_on_clauses = deepcopy(global_state_update_on_clauses)
              old_object_specific_state_update_on_clauses = deepcopy(object_specific_state_update_on_clauses)
              old_state_update_on_clauses = deepcopy(state_update_on_clauses)

              # update current problem context with state solution 
              curr_state_solution = state_solutions[1]
              new_on_clauses, new_global_var_dict, new_state_update_times_dict = curr_state_solution 
              
              # formatting 
              group_addObj_rules, addObj_rules, addObj_count = addObj_params_dict[type_id]
              formatted_on_clauses = map(on_clause -> format_on_clause(split(replace(on_clause, ".. obj id) x" => ".. obj id) $(object_ids[1])"), "\n")[2][1:end-1], replace(replace(split(on_clause, "\n")[1], "(on " => ""), ".. obj id) x" => ".. obj id) $(object_ids[1])"), object_ids_with_type[1], object_ids_with_type, object_type, group_addObj_rules, addObj_rules, object_mapping, true, grid_size, addObj_count), new_on_clauses)
              push!(on_clauses, formatted_on_clauses...)
              
              global_var_dict = deepcopy(new_global_var_dict) 
              global_state_update_on_clauses = vcat(map(k -> filter(x -> x != "", new_state_update_times_dict[k]), collect(keys(new_state_update_times_dict)))...) # vcat(state_update_on_clauses..., filter(x -> x != "", new_state_update_times)...)
              state_update_on_clauses = vcat(global_state_update_on_clauses, object_specific_state_update_on_clauses)
              global_state_update_times_dict = new_state_update_times_dict

              state_update_on_clauses = unique(state_update_on_clauses)
              on_clauses = unique(on_clauses)

              println("ADDING EVENT WITH NEW STATE")
              @show update_rule
              @show on_clause
              @show length(on_clauses)
              @show on_clauses

              for state_solution in state_solutions[2:end]
                # add new problem contexts 
                new_context_on_clauses, new_context_new_global_var_dict, new_context_new_state_update_times_dict = state_solutions[sol_index]

                new_context_on_clauses = deepcopy(old_on_clauses)
                new_context_global_object_decomposition = deepcopy(old_global_object_decomposition)
                new_context_global_state_update_times_dict = deepcopy(old_global_state_update_times_dict)
                new_context_object_specific_state_update_times_dict = deepcopy(old_object_specific_state_update_times_dict)
                new_context_global_state_update_on_clauses = deepcopy(old_global_state_update_on_clauses)
                new_context_object_specific_state_update_on_clauses = deepcopy(old_object_specific_state_update_on_clauses)
                new_context_state_update_on_clauses = deepcopy(old_state_update_on_clauses)

                formatted_new_context_on_clauses = map(on_clause -> format_on_clause(split(replace(on_clause, ".. obj id) x" => ".. obj id) $(object_ids[1])"), "\n")[2][1:end-1], replace(replace(split(on_clause, "\n")[1], "(on " => ""), ".. obj id) x" => ".. obj id) $(object_ids[1])"), object_ids_with_type[1], object_ids_with_type, object_type, group_addObj_rules, addObj_rules, object_mapping, true, grid_size, addObj_count), new_context_on_clauses)
                push!(new_context_on_clauses, formatted_new_context_on_clauses...)
                new_context_global_var_dict = new_context_new_global_var_dict
                new_context_global_state_update_on_clauses = vcat(map(k -> filter(x -> x != "", new_context_new_state_update_times_dict[k]), collect(keys(new_context_new_state_update_times_dict)))...) # vcat(state_update_on_clauses..., filter(x -> x != "", new_state_update_times)...)
                new_context_state_update_on_clauses = vcat(new_context_global_state_update_on_clauses, new_context_object_specific_state_update_on_clauses)
                new_context_global_state_update_times_dict = new_context_new_state_update_times_dict

                new_context_state_update_on_clauses = unique(new_context_state_update_on_clauses)
                new_context_on_clauses = unique(new_context_on_clauses)

                problem_context = (deepcopy(co_occurring_events_dict), 
                                   new_context_on_clauses,
                                   new_context_global_var_dict,
                                   new_context_global_object_decomposition, 
                                   new_context_global_state_update_times_dict,
                                   new_context_object_specific_state_update_times_dict,
                                   new_context_global_state_update_on_clauses,
                                   new_context_object_specific_state_update_on_clauses,
                                   new_context_state_update_on_clauses )

                push!(problem_contexts, problem_context)

              end
            end
          else 
            # construct new object-specific state
            if length(update_functions) > 1 
              failed = true 
              break
            else 
              update_function = update_functions[1]
              update_function_times_dict = Dict()
              for object_id in object_ids_with_type
                update_function_times_dict[object_id] = times_dict[update_function][object_id]
              end
              on_clause, new_state_update_on_clauses, new_object_decomposition, new_object_specific_state_update_times_dict = generate_new_object_specific_state(update_function, update_function_times_dict, event_vector_dict, type_id, global_object_decomposition, object_specific_state_update_times_dict, global_var_dict)            
              
              if on_clause == "" 
                failed = true 
                break
              else
                # # @show new_object_specific_state_update_times_dict
                object_specific_state_update_times_dict = new_object_specific_state_update_times_dict
    
                # on_clause = format_on_clause(split(on_clause, "\n")[2][1:end-1], replace(replace(split(on_clause, "\n")[1], "(on " => ""), "(== (.. obj id) x)" => "(== (.. obj id) $(object_ids[1]))"), object_ids[1], object_ids, object_type, group_addObj_rules, addObj_rules, object_mapping, false)
                push!(on_clauses, on_clause)
    
                global_object_decomposition = new_object_decomposition
                object_types, object_mapping, background, dim = global_object_decomposition
                
                println("UPDATEEE")
                # # @show global_object_decomposition
    
                # new_state_update_on_clauses = map(x -> format_on_clause(split(x, "\n")[2][1:end-1], replace(split(x, "\n")[1], "(on " => ""), object_ids[1], object_ids, object_type, group_addObj_rules, addObj_rules, object_mapping, false), new_state_update_on_clauses)
                object_specific_state_update_on_clauses = unique(vcat(object_specific_state_update_on_clauses..., new_state_update_on_clauses...))
                state_update_on_clauses = vcat(global_state_update_on_clauses, object_specific_state_update_on_clauses)
                for event in collect(keys(global_event_vector_dict))
                  if occursin("field1", event)
                    delete!(global_event_vector_dict, event)
                  end
                end

                state_update_on_clauses = unique(state_update_on_clauses)
                on_clauses = unique(on_clauses)  
              end
            end
          end

          # check if newly created state solves any of the other remaining update functions 
          new_on_clauses, state_based_update_functions_dict, _, _ = generate_stateless_on_clauses(update_functions_dict, matrix, filtered_matrix, anonymized_filtered_matrix, global_object_decomposition, user_events, state_update_on_clauses, global_var_dict, global_event_vector_dict, redundant_events_set)
          
          # if some other update functions are solved, add their on-clauses + remove them from co_occurring_events_dict 
          if new_on_clauses != [] 
            push!(on_clauses, new_on_clauses)
            # update co_occurring_events_dict by removing 
            co_occurring_events_dict = update_co_occurring_events_dict(co_occurring_events_dict, state_based_update_functions_dict)
          end

        end

        if failed
          # move to new problem context because appropriate state was not found  
          break
        else
          push!(solutions, )
        end

      end
    end 
  end
  @show solutions 
  solutions 
end


function update_co_occurring_events_dict(co_occurring_events_dict, state_based_update_functions_dict) 
  # remove solved update functions from co_occurring_events_dict
  for tuple in keys(co_occurring_events_dict) 
    co_occurring_events_dict[tuple] = filter(upd_func -> (tuple[1] in keys(state_based_update_functions_dict))
                                                          && (upd_func in state_based_update_functions_dict[tuple[1]]), 
                                             co_occurring_events_dict[tuple])
  end

  # remove co-occurring events associated with no update functions 
  co_occurring_tuples = deepcopy(collect(keys(co_occurring_events_dict)))
  for tuple in co_occurring_events
    if length(co_occurring_events_dict[tuple]) == 0 
      delete!(co_occurring_events_dict, tuple)
    end
  end
  co_occurring_events_dict
end

function generate_new_state_GLOBAL(co_occurring_event, times_dict, event_vector_dict, object_trajectory, init_global_var_dict, state_update_times_dict, object_decomposition, type_id, desired_per_matrix_solution_count) 
  println("GENERATE_NEW_STATE_GLOBAL")
  @show times_dict 
  @show event_vector_dict 
  @show object_trajectory    
  @show init_global_var_dict 
  @show state_update_times_dict   
  init_state_update_times_dict = deepcopy(state_update_times_dict)
  failed = false
  solutions = []

  # construct update_function_times 
  update_function_times_dict = Dict(map(u -> u => unique(vcat(map(obj_id -> times_dict[u][obj_id], collect(keys(times_dict[u])))...) ), collect(keys(times_dict))))

  events = filter(e -> event_vector_dict[e] isa AbstractArray, collect(keys(event_vector_dict)))
  atomic_events = gen_event_bool_human_prior(object_decomposition, "x", type_id, ["nothing"], init_global_var_dict, update_rule)
  small_event_vector_dict = deepcopy(event_vector_dict)    
  for e in keys(event_vector_dict)
    if !(e in atomic_events) || !(event_vector_dict[e] isa AbstractArray)
      delete!(small_event_vector_dict, e)
    end
  end

  co_occurring_event_trajectory = event_vector_dict[co_occurring_event]

  # initialize global_var_dict and get global_var_value
  if length(collect(keys(init_global_var_dict))) == 0 
    init_global_var_dict[1] = ones(Int, length(init_state_update_times_dict[1]))
    global_var_id = 1
  else # check if all update function times match with one value of init_global_var_dict
    global_var_id = maximum(collect(keys(init_global_var_dict))) + 1 
    init_global_var_dict[global_var_id] = ones(Int, length(init_state_update_times_dict[1]))
  end

  true_positive_times = update_function_times # times when co_occurring_event happened and update_rule happened 
  false_positive_times = [] # times when user_event happened and update_rule didn't happen

  # construct true_positive_times and false_positive_times 
  # # @show length(user_events)
  # # @show length(co_occurring_event_trajectory)
  for time in 1:length(co_occurring_event_trajectory)
    if co_occurring_event_trajectory[time] == 1 && !(time in true_positive_times)
      if occursin("addObj", update_rule)
        push!(false_positive_times, time)
      elseif (object_trajectory[time][1] != "") && !(occursin("addObj", object_trajectory[time][1]))
        push!(false_positive_times, time)
      end     
    end
  end

  # compute ranges in which to search for events 
  ranges = []

  update_functions = collect(keys(times_dict))
  update_function_indices = Dict(map(u -> u => findall(x -> x == u, update_functions)[1], update_functions))
  global_var_value = length(update_functions)

  # construct augmented true positive times 
  augmented_true_positive_times_dict = Dict(map(u -> u => map(t -> (t, update_function_indices[u]), update_function_times_dict[u]), update_functions))
  augmented_true_positive_times = vcat(collect(values(augmented_true_positive_times_dict))...)  
  
  # construct augmented false positive times 
  false_positive_times = []
  for time in 1:length(co_occurring_event_trajectory)
    if co_occurring_event_trajectory[time] == 1 && !(time in map(tuple -> tuple[1], augmented_true_positive_times))
      if occursin("addObj", update_rule)
        push!(false_positive_times, time)
      elseif (object_trajectory[time][1] != "") && !(occursin("addObj", object_trajectory[time][1]))
        push!(false_positive_times, time)
      end     
    end
  end

  augmented_false_positive_times = map(t -> (t, global_var_value + 1), false_positive_times)
  init_augmented_positive_times = sort(vcat(augmented_true_positive_times, augmented_false_positive_times), by=x -> x[1])

  for i in 1:(length(init_augmented_positive_times)-1)
    prev_time, prev_value = init_augmented_positive_times[i]
    next_time, next_value = init_augmented_positive_times[i + 1]
    if prev_value != next_value
      push!(ranges, (init_augmented_positive_times[i], init_augmented_positive_times[i + 1]))
    end
  end
  println("WHY THO")
  # @show init_state_update_times_dict 

  # filter ranges where both the range's start and end times are already included
  ranges = unique(ranges)
  new_ranges = []
  for range in ranges
    start_tuples = map(range -> range[1], filter(r -> r != range, ranges))
    end_tuples = map(range -> range[2], filter(r -> r != range, ranges))
    if !((range[1] in start_tuples) && (range[2] in end_tuples))
      push!(new_ranges, range)      
    end
  end

  init_grouped_ranges = group_ranges(new_ranges)
  # @show init_grouped_ranges

  init_extra_global_var_values = Dict(map(u -> update_function_indices[u] => [], update_functions))

  problem_contexts = [(deepcopy(init_grouped_ranges), deepcopy(init_augmented_positive_times), deepcopy(init_state_update_times_dict), deepcopy(init_global_var_dict), deepcopy(init_extra_global_var_values))]
  split_orders = []
  while (length(problem_contexts) > 0) && length(solutions) < desired_per_matrix_solution_count 
    grouped_ranges, augmented_positive_times, new_state_update_times_dict, global_var_dict, extra_global_var_values = problem_contexts[1]
    problem_contexts = problem_contexts[2:end]

    # curr_max_grouped_ranges = deepcopy(grouped_ranges)
    # curr_max_augmented_positive_times = deepcopy(augmented_positive_times)
    # curr_max_new_state_update_times_dict = deepcopy(new_state_update_times_dict)
    # curr_max_global_var_dict = deepcopy(global_var_dict)

    # while there are ranges that need to be explained, search for explaining events within them
    while length(grouped_ranges) > 0
      # if Set([grouped_ranges..., curr_max_grouped_ranges...]) != Set(curr_max_grouped_ranges)
      #   curr_max_grouped_ranges = deepcopy(grouped_ranges)
      #   curr_max_augmented_positive_times = deepcopy(augmented_positive_times)
      #   curr_max_new_state_update_times_dict = deepcopy(new_state_update_times_dict)
      #   curr_max_global_var_dict = deepcopy(global_var_dict)
      # end

      grouped_range = grouped_ranges[1]
      grouped_ranges = grouped_ranges[2:end] # remove first range from ranges 
  
      range = grouped_range[1]
      start_value = range[1][2]
      end_value = range[2][2]
  
      time_ranges = map(r -> (r[1][1], r[2][1] - 1), grouped_range)
  
      # construct state update function
      state_update_function = "(= globalVar$(global_var_id) $(end_value))"
  
      # get current maximum value of globalVar
      max_global_var_value = maximum(map(tuple -> tuple[2], augmented_positive_times))
  
      # search for events within range
      events_in_range = find_state_update_events(small_event_vector_dict, augmented_positive_times, time_ranges, start_value, end_value, global_var_dict, global_var_id, global_var_value)
      if events_in_range != [] # event with zero false positives found
        println("PLS WORK 2")
        # # @show event_vector_dict
        # @show events_in_range 
        if filter(tuple -> !occursin("true", tuple[1]), events_in_range) != []
          if filter(tuple -> !occursin("globalVar", tuple[1]) && !occursin("true", tuple[1]), events_in_range) != []
            state_update_event, event_times = filter(tuple -> !occursin("globalVar", tuple[1]) && !occursin("true", tuple[1]), events_in_range)[1]
          else
            state_update_event, event_times = filter(tuple -> !occursin("true", tuple[1]), events_in_range)[1]
          end
        else 
          # FAILURE CASE 
          state_update_event, event_times = events_in_range[1]
        end
  
        # construct state update on-clause
        state_update_on_clause = "(on $(state_update_event)\n$(state_update_function))"
        
        # add to state_update_times 
        # # @show event_times
        # # @show state_update_on_clause  
        for time in event_times 
          new_state_update_times_dict[global_var_id][time] = state_update_on_clause
        end
  
      else # no event with zero false positives found; use best false-positive event and specialize globalVar values (i.e. add new value)
        # find co-occurring event with fewest false positives 
        false_positive_events = find_state_update_events_false_positives(small_event_vector_dict, augmented_positive_times, time_ranges, start_value, end_value, global_var_dict, global_var_id, global_var_value)
        false_positive_events_with_state = filter(e -> occursin("globalVar$(global_var_id)", e[1]), false_positive_events) # want the most specific events in the false positive case
        
        events_without_true = filter(tuple -> !occursin("true", tuple[1]) && tuple[2] == minimum(map(t -> t[2], false_positive_events_with_state)), false_positive_events_with_state)
        if events_without_true != []
          false_positive_event, _, true_positive_times, false_positive_times = events_without_true[1] 
        else
          # FAILURE CASE: only separating event with false positives is true-based 
          # false_positive_event, _, true_positive_times, false_positive_times = false_positive_events_with_state[1]
          failed = true 
          break  
        end

        # if the selected false positive event falls into a different transition range, create a new problem context with
        # the order of those ranges switched
        matching_grouped_ranges = filter(grouped_range -> intersect(vcat(map(r -> collect(r[1][1]:(r[2][1] - 1)), grouped_range)...), false_positive_times) != [], grouped_ranges) 

        # @show length(matching_grouped_ranges)
        if length(matching_grouped_ranges) > 0 
          println("WOAHHH")
          if length(matching_grouped_ranges[1]) > 0 
            println("WOAHHH 2")
          end
        end
        
        if length(matching_grouped_ranges) == 1 && length(matching_grouped_ranges[1]) == 1
          matching_grouped_range = matching_grouped_ranges[1]
          matching_range = matching_grouped_range[1]
          matching_values = (matching_range[1][2], matching_range[2][2])
          current_values = (start_value, end_value)

          # @show matching_grouped_range
          # @show matching_range
          # @show matching_values
          # @show current_values

          # check that we haven't previously considered this reordering
          if !((current_values, matching_values) in split_orders) # && !((matching_values, current_values) in split_orders)
            push!(split_orders, (current_values, matching_values))

            # create new problem context
            new_context_grouped_ranges, new_context_augmented_positive_times, new_context_new_state_update_times_dict = recompute_ranges(deepcopy(augmented_positive_times), 
                                                                                                                                         deepcopy(new_state_update_times_dict),
                                                                                                                                         global_var_id, 
                                                                                                                                         global_var_value,
                                                                                                                                         deepcopy(global_var_dict),
                                                                                                                                         deepcopy(true_positive_times), 
                                                                                                                                         deepcopy(extra_global_var_values))
            # new_context_grouped_ranges = deepcopy(curr_max_grouped_ranges)
            # @show grouped_ranges
            # @show new_context_grouped_ranges
            matching_idx = findall(r -> r[1][1][2] == matching_values[1] && r[1][2][2] == matching_values[2], new_context_grouped_ranges)[1]
            curr_idx = findall(r -> r[1][1][2] == current_values[1] && r[1][2][2] == current_values[2], new_context_grouped_ranges)[1]
            
            new_context_grouped_ranges[curr_idx] = deepcopy(matching_grouped_range) 
            new_context_grouped_ranges[matching_idx] = deepcopy(grouped_range)

            # new_context_augmented_positive_times = deepcopy(curr_max_augmented_positive_times)
            # new_context_new_state_update_times_dict = deepcopy(curr_max_new_state_update_times_dict) 
            # new_context_curr_max_global_var_dict = deepcopy(curr_max_global_var_dict)

            # if the false positive intersection with a different range has size greater than 1, try allowing the first false
            # positive event in that other range to take place, instead of specializing its value
            intersecting_times = intersect(collect(matching_range[1][1]:(matching_range[2][1] - 1)), false_positive_times)
            if length(intersecting_times) > 1
              # update new_context_augmented_positive_times 
              first_intersecting_time = intersecting_times[1]
              push!(new_context_augmented_positive_times, (first_intersecting_time + 1, end_value))
              sort!(new_context_augmented_positive_times, by=x -> x[1])
              # recompute ranges + state_update_times_dict
              new_context_grouped_ranges, new_context_augmented_positive_times, new_context_new_state_update_times_dict = recompute_ranges(new_context_augmented_positive_times, 
                                                                                                                                           deepcopy(init_state_update_times_dict),
                                                                                                                                           global_var_id, 
                                                                                                                                           global_var_value,
                                                                                                                                           deepcopy(global_var_dict),
                                                                                                                                           true_positive_times, 
                                                                                                                                           extra_global_var_values)
            end

            push!(problem_contexts, (new_context_grouped_ranges, new_context_augmented_positive_times, deepcopy(init_state_update_times_dict), deepcopy(global_var_dict), deepcopy(extra_global_var_values)))
          end
        end
  
        # construct state update on-clause
        state_update_on_clause = "(on $(false_positive_event)\n$(state_update_function))"
        
        # add to state_update_times
        for time in true_positive_times 
          new_state_update_times_dict[global_var_id][time] = state_update_on_clause            
        end
        
        augmented_positive_times_labeled = map(tuple -> (tuple[1], tuple[2], "update_function"), augmented_positive_times) 
        for time in false_positive_times  
          push!(augmented_positive_times_labeled, (time, max_global_var_value + 1, "event"))
        end
        same_time_tuples = Dict()
        for tuple in augmented_positive_times_labeled
          time = tuple[1] 
          if time in collect(keys((same_time_tuples))) 
            push!(same_time_tuples[time], tuple)
          else
            same_time_tuples[time] = [tuple]
          end
        end
  
        for time in collect(keys((same_time_tuples))) 
          same_time_tuples[time] = reverse(sort(same_time_tuples[time], by=x -> length(x[3]))) # ensure all event tuples come *after* the update_function tuples
        end
        augmented_positive_times_labeled = vcat(map(t -> same_time_tuples[t], sort(collect(keys(same_time_tuples))))...)
        # augmented_positive_times_labeled = sort(augmented_positive_times_labeled, by=x->x[1])
  
        # relabel false positive times 
        # based on relabeling, relabel other existing labels if necessary 
        for tuple_index in 1:length(augmented_positive_times_labeled)
          tuple = augmented_positive_times_labeled[tuple_index]
          if tuple[3] == "event"
            for prev_index in (tuple_index-1):-1:1
              prev_tuple = augmented_positive_times_labeled[prev_index]
              
              if prev_tuple[2] <= global_var_value || prev_tuple[2] in vcat(collect(values(extra_global_var_values))...)
                println("HERE 2")
                @show prev_tuple 
                @show tuple
                if prev_tuple[1] == tuple[1] && !(prev_tuple[2] in vcat(collect(values(extra_global_var_values))...)) # if the false positive time is the same as the global_var_value time, change the value
                  println("HERE")

                  augmented_positive_times_labeled[prev_index] = (prev_tuple[1], max_global_var_value + 1, prev_tuple[3])
                  # find update function index that contains this time 
                  update_function = filter(k -> prev_tuple[1] in update_function_times_dict[k], collect(keys(update_function_times_dict)))[1]
                  update_function_index = update_function_indices[update_function]

                  push!(extra_global_var_values[update_function_index], max_global_var_value + 1)
                  break
                else # if the two times are different, stop the relabeling process w.r.t. to this false positive tuple 
                  break
                end
              end
              
              if (prev_tuple[2] > global_var_value) && !(prev_tuple[2] in vcat(collect(values(extra_global_var_values))...)) ) && (prev_tuple[3] == "update_function")
                augmented_positive_times_labeled[prev_index] = (prev_tuple[1], max_global_var_value + 1, prev_tuple[3])
              end
            end
          end
        end
        augmented_positive_times = map(t -> (t[1], t[2]), filter(tuple -> tuple[3] == "update_function", augmented_positive_times_labeled))      
  
        # compute new ranges and find state update events
        grouped_ranges, augmented_positive_times, new_state_update_times_dict = recompute_ranges(augmented_positive_times, new_state_update_times_dict, global_var_id, global_var_value, global_var_dict, true_positive_times, extra_global_var_values)
      end
    end
  
    if failed 
      solution = ("", global_var_dict, new_state_update_times_dict)
      push!(solutions, solution)
    else
      # update global_var_dict
      _, init_value = augmented_positive_times[1]                                   
      for time in 1:length(global_var_dict[global_var_id]) 
        if global_var_dict[global_var_id][time] >= global_var_value 
          global_var_dict[global_var_id][time] = init_value
        end
      end
  
      curr_value = -1
      for time in 1:length(global_var_dict[global_var_id])
        if curr_value != -1 
          global_var_dict[global_var_id][time] = curr_value
        end
        if new_state_update_times_dict[global_var_id][time] != ""
          curr_value = parse(Int, split(split(new_state_update_times_dict[global_var_id][time], "\n")[2], "(= globalVar$(global_var_id) ")[2][1])
        end
      end
      
      on_clauses = []
      for update_function in update_functions 
        update_function_index = update_function_indices[update_function]
        if extra_global_var_values[update_function_index] == [] 
          on_clause = "(on $(occursin("globalVar$(global_var_id)", co_occurring_event) ? co_occurring_event : "(& (== (prev globalVar$(global_var_id)) $(update_function_index)) $(co_occurring_event))")\n$(update_function))"
        else 
          on_clause = "(on (& (in (prev globalVar$(global_var_id)) (list $(join([update_function_index, extra_global_var_values[update_function_index]...], " ")))) $(occursin("globalVar$(global_var_id)", co_occurring_event) ? replace(replace(co_occurring_event, "(== globalVar$(global_var_id) $(update_function_index))" => ""), "(&" => "")[1:end-1] : co_occurring_event))\n$(update_rule))"
        end
        push!(on_clauses, on_clause)
      end
      
      solution = (on_clauses, global_var_dict, new_state_update_times_dict)
      push!(solutions, solution)
    end
  end
  sort(solutions, by=sol -> length(unique(sol[2][1])))
end

function generate_stateless_on_clauses(update_functions_dict, matrix, filtered_matrix, anonymized_filtered_matrix, global_object_decomposition, user_events, state_update_on_clauses, global_var_dict, global_event_vector_dict, redundant_events_set)
  object_types, object_mapping, background, grid_size = global_object_decomposition
  new_on_clauses = []
  event_vectors_dict = Dict() 
  addObj_params_dict = Dict()
  state_based_update_functions_dict = Dict()
  
  type_ids = sort(collect(keys(update_functions_dict)))
  for type_id in type_ids
    object_type = filter(t -> t.id == type_id, object_types)
    object_ids = sort(filter(id -> filter(obj -> !isnothing(obj), object_mapping[id])[1].type.id == type_id, collect(keys(object_mapping))))

    all_update_rules = filter(rule -> rule != "", unique(vcat(vec(anonymized_filtered_matrix[object_ids, :])...)))

    update_rule_set = vcat(filter(r -> r != "", vcat(map(id -> map(x -> replace(x[1], "obj id) $(id)" => "obj id) x"), filtered_matrix[id, :]), object_ids)...))...)

    addObj_rules = filter(rule -> occursin("addObj", rule), vcat(map(id -> vcat(filtered_matrix[id, :]...), object_ids)...))
    unique_addObj_rules = unique(filter(rule -> occursin("addObj", rule), vcat(map(id -> vcat(filtered_matrix[id, :]...), object_ids)...)))
    addObj_times_dict = Dict()

    for rule in unique_addObj_rules 
      addObj_times_dict[rule] = sort(unique(vcat(map(id -> findall(r -> r == rule, vcat(filtered_matrix[id, :]...)), object_ids)...)))
    end
    
    group_addObj_rules = false
    addObj_count = 0
    if length(unique(collect(values(addObj_times_dict)))) == 1
      group_addObj_rules = true
      all_update_rules = filter(r -> !(r in addObj_rules), all_update_rules)
      push!(all_update_rules, addObj_rules[1]) 
      addObj_count = count(r -> occursin("addObj", r), vcat(filtered_matrix[:, collect(values(addObj_times_dict))[1][1]]...))
    end

    # construct addObj_params_dict
    addObj_params_dict[type_id] = (group_addObj_rules, addObj_rules, addObj_count)
    
    no_change_rules = filter(x -> is_no_change_rule(x), unique(all_update_rules))
    all_update_rules = reverse(sort(filter(x -> !is_no_change_rule(x), all_update_rules), by=x -> count(y -> y == x, update_rule_set)))
    all_update_rules = [no_change_rules..., all_update_rules...]

    update_functions = update_functions_dict[type_id]
    for update_rule in update_functions
      # @show update_rule_index 
      # @show length(all_update_rules)
      # update_rule = all_update_rules[update_rule_index]
      # # @show global_object_decomposition
      if update_rule != "" && !is_no_change_rule(update_rule)
        println("UPDATE_RULEEE")
        println(update_rule)
        events, event_is_globals, event_vector_dict, observation_data_dict = generate_event(update_rule, object_ids[1], object_ids, matrix, filtered_matrix, global_object_decomposition, user_events, state_update_on_clauses, global_var_dict, global_event_vector_dict, grid_size, redundant_events_set)
        global_event_vector_dict = event_vector_dict
        event_vectors_dict[update_rule] = observation_data_dict

        println("EVENTS")
        println(events)
        # # @show event_vector_dict
        # # @show observation_data_dict
        if events != []
          event = events[1]
          event_is_global = event_is_globals[1]
          on_clause = format_on_clause(replace(update_rule, ".. obj id) x" => ".. obj id) $(object_ids[1])"), replace(event, ".. obj id) x" => ".. obj id) $(object_ids[1])"), object_ids[1], object_ids, object_type, group_addObj_rules, addObj_rules, object_mapping, event_is_global, grid_size, addObj_count)
          push!(new_on_clauses, on_clause)
          new_on_clauses = unique(new_on_clauses)
          println("ADDING EVENT WITHOUT NEW STATE")
          @show event 
          @show update_rule
          @show on_clause
          @show length(on_clauses)
          @show on_clauses
        else # collect update functions for later state generation
          if type_index in state_based_update_functions_dict
            push!(state_based_update_functions_dict[type_index], update_rule)
          else
            state_based_update_functions_dict[type_index] = update_rule 
          end
        end 

      end

    end
  end

  new_on_clauses, state_based_update_functions_dict, event_vectors_dict, addObj_params_dict 
end