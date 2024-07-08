from juliacall import Pkg # if there's an error after this command, just try the command again
Pkg.activate('.')
Pkg.add(url="https://github.com/riadas/Autumn.jl#cs-eachindex") # suppose to get precompilation errors here
Pkg.add(url='https://github.com/topwasu/SExpressions.jl.git')
Pkg.update()