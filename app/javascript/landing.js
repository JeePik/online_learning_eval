document.addEventListener("DOMContentLoaded", () => {

  const form = document.querySelector("form");
  const loader = document.getElementById("loader");

  if(form){

    form.addEventListener("submit", () => {
      loader.style.display = "block";
    });

  }

});
