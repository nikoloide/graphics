require 'thingy'

WINSIZE = 500

class Float
  ##
  # A floating-point friendly `between?` function that excludes
  # the lower bound.
  # Equivalent to `min < x <= max`
  ##
  def xbetween? min, max
    min < self && self <= max
  end
end

class Vec2 < Struct.new(:x, :y)
  ZERO = Vec2.new 0, 0

  def + other
    Vec2.new x+other.x, y+other.y
  end

  def - other
    Vec2.new x-other.x, y-other.y
  end

  def * s
    Vec2.new x*s, y*s
  end

  def / s
    Vec2.new x/s, y/s
  end

  def == other
    x == other.x && y == other.y
  end

  def magnitude
    Math.sqrt(x*x + y*y)
  end
end

class Particle
  attr_accessor :density, :position, :velocity,
                :pressure_force, :viscosity_force
  def initialize pos
    # Scalars
    @density = 0

    # Forces
    @position        = pos
    @velocity        = Vec2::ZERO
    @pressure_force  = Vec2::ZERO
    @viscosity_force = Vec2::ZERO
  end
end

##
# Constants
#

NUM_PARTICLES = 150
MASS          = 5  # Particle mass
DENSITY       = 1  # Rest density
GRAVITY       = Vec2.new 0, -0.5
H             = 1  # Smoothing cutoff- essentially, particle size
H2 = H*H
K             = 20 # Temperature constant- higher means particle repel more strongly
ETA           = 1  # Viscosity constant- higher for more viscous

##
# A weighting function (kernel) for the contribution of each neighbor
# to a particle's density. Forms a nice smooth gradient from the center
# of a particle to H, where it's 0
#

def W r, h
  len_r2 = r.magnitude

  if len_r2.xbetween? 0, h*h
    315.0/(64 * Math::PI * h**9) * (h**2 - len_r2)**3
  else
    0.0
  end
end

##
# Gradient ( that is, Vec2(dx, dy) ) of a weighting function for
# a particle's pressure. This weight function is spiky (not flat or
# smooth at x=0) so particles close together repel strongly.
#

def gradient_Wspiky r, h
  len_r2 = r.magnitude

  if len_r2.xbetween? 0, h*h
    s = (45.0/(Math::PI * h**6 * len_r2)) * (h*h - len_r2) * (-1.0)
    r * s
  else
    Vec2::ZERO
  end
end

##
# The laplacian of a weighting function that tends towards infinity when
# approching 0 (slows down particles moving faster than their neighbors)
#

def laplacian_W_viscosity r, h
  len_r2 = r.magnitude

  if len_r2.xbetween? 0, h*h
    45.0/(2 * Math::PI * h**5) * (1 - len_r2/h)
  else
    0.0
  end
end

class SPH
  attr_reader :particles
  def initialize
    # Instantiate particles!
    @particles = []
    (0..10).each do |x|
      (0..10).each do |y|
        jitter = rand * 0.1
        particles << Particle.new(Vec2.new x+1+jitter, y+5)
      end
    end
  end

  def step delta_time

    # Clear everything
    particles.each do |particle|
      particle.density = DENSITY
      particle.pressure_force = Vec2::ZERO
      particle.viscosity_force = Vec2::ZERO
    end

    # Calculate fluid density around each particle
    particles.each do |particle|
      particles.each do |neighbor|

        # If particles are close together, density increases
        distance = particle.position - neighbor.position

        if distance.magnitude < H2  # Particles are close enough to matter
          particle.density += MASS * W(distance, H)
        end
      end
    end

    # Calculate forces on each particle based on density
    particles.each do |particle|
      particles.each do |neighbor|

        distance = particle.position - neighbor.position
        if  distance.magnitude <= H2
          # Temporary terms used to caclulate forces
          density_p = particle.density
          density_n = neighbor.density
          # This *should* never happen, but it's good to check,
          # because we're dividing by density later
          raise "Particle density is, impossibly, 0" unless density_n != 0

          # Pressure derived from the ideal gas law (constant temp)
          pressure_p = K * (density_p - DENSITY)
          pressure_n = K * (density_n - DENSITY)

          # Navier-Stokes equations for pressure and viscosity
          # (ignoring surface tension)
          particle.pressure_force +=
            gradient_Wspiky(distance, H) *
            (-1.0 * MASS * (pressure_p + pressure_n) / (2 * density_n))

          particle.viscosity_force +=
            (neighbor.velocity - particle.velocity) *
            (ETA * MASS * (1/density_n) * laplacian_W_viscosity(distance, H))
        end
      end
    end

    # Apply forces to particles- make them move!
    particles.each do |particle|
      total_force = particle.pressure_force + particle.viscosity_force

      # 'Eulerian' style momentum:

      # Calculate acceleration from forces
      acceleration = (total_force * (1.0/particle.density*delta_time)) + GRAVITY

      # Update position and velocity
      particle.velocity += acceleration * delta_time
      particle.position += particle.velocity * delta_time
    end
  end

  ##
  # The walls nudge particles back in-bounds, plus a little jitter
  # so nothing gets stuck
  #

  def make_particles_stay_in_bounds scale
    # TODO: Better boundary conditions (THESE ARE A LAME WORKAROUND)
    particles.each do |particle|
      if particle.position.x >= scale - 0.01
        particle.position.x = scale - (0.01 + 0.1*rand)
        particle.velocity.x = 0
      elsif particle.position.x < 0.01
        particle.position.x = 0.01 + 0.1*rand
        particle.velocity.x = 0
      end

      if particle.position.y >= scale - 0.01
        particle.position.y = scale - (0.01+rand*0.1)
        particle.velocity.y = 0
      elsif particle.position.y < 0.01
        particle.position.y = 0.01 + rand*0.1
        particle.velocity.y = 0
      end
    end
  end

end

class SimulationWindow < Thingy
  attr_reader :simulation
  def initialize
    super WINSIZE, WINSIZE, 16, "Smoothed Particle Hydrodynamics"
    @simulation = SPH.new
    @scale = 15
    @oldtime = 0.0
  end

  def update time
    simulation.step 0.1
    simulation.make_particles_stay_in_bounds @scale
  end

  def draw time
    clear
    s = WINSIZE.div @scale

    simulation.particles.each do |particle|

      # Particles
      ellipse((particle.position.x*s).to_i,
              (particle.position.y*s).to_i,
              5,
              5,
              :white)

      # Velocity vectors
      line((particle.position.x*s),                       # start
           (particle.position.y*s),
           ((particle.position.x+particle.velocity.x)*s), # end
           ((particle.position.y+particle.velocity.y)*s),
           :red)

      fps time
    end
  end
end

SimulationWindow.new.run